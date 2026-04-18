# frozen_string_literal: true

require 'socket'
require 'json'
require 'thread'
require 'pathname'

module ReentrantSketchup
  # Minimal MCP (Model Context Protocol) server over HTTP.
  # Lets Claude Code (or any MCP client) connect and drive SketchUp.
  #
  # Protocol: JSON-RPC 2.0 over HTTP POST to /mcp
  # Thread safety: request handlers that touch the SketchUp model are queued
  # and executed on the main thread via a UI.start_timer pump.
  module McpServer
    DEFAULT_PORT = 3636
    PROTOCOL_VERSION = '2025-06-18'
    MAX_RESULT_BYTES = 4096
    MAX_SCRIPT_FILE_BYTES = 1 * 1024 * 1024  # 1 MB
    DEFAULT_TIMEOUT_S = 30

    # Sentinel returned by on_main_thread when the wait deadline is reached.
    # Does not interrupt the queued lambda — it will still run when the main
    # thread gets around to it (SketchUp can't safely interrupt Ruby running
    # a C-level API call). The caller handles this sentinel and returns
    # status: 'timeout' to the MCP client.
    MAIN_THREAD_TIMEOUT = :__mcp_main_thread_timeout__

    @server_thread = nil
    @tcp_server = nil
    @main_pump_timer = nil
    @queue = []
    @queue_mutex = Mutex.new
    @port = DEFAULT_PORT
    @open_operations = 0
    @snapshot = { fetched_at_ms: nil, status: 'pending' }.freeze
    @snapshot_mutex = Mutex.new
    @tick_count = 0
    SNAPSHOT_REFRESH_EVERY_N_TICKS = 10  # pump runs every 50ms, so ~500ms

    TOOLS = [
      {
        name: 'get_selection',
        description: 'Current SketchUp selection. Response: {status, count, types}.',
        inputSchema: { type: 'object', properties: {}, required: [] }
      },
      {
        name: 'get_model_info',
        description: 'Active model summary. Response: {status, title, path, entities, definitions, materials, layers}. For a diagnostic snapshot that works even when execute_ruby is stuck, prefer probe.',
        inputSchema: { type: 'object', properties: {}, required: [] }
      },
      {
        name: 'list_entities',
        description: 'List entities in the active context with their types. Response: {status, entities:[{type, typename}], total}.',
        inputSchema: {
          type: 'object',
          properties: {
            limit: { type: 'integer', description: 'Max entities to return', default: 50 }
          }
        }
      },
      {
        name: 'execute_ruby',
        description: 'Execute Ruby in the SketchUp context. Atomic by default — wraps execution in a SketchUp undo operation and aborts on any exception. Response on success: {status:"ok", result, result_class, elapsed_ms, entity_count, op_name}. On raise: {status:"error", error, message, backtrace, elapsed_ms, op_name}. On server-side timeout (client exceeded timeout_s): {status:"timeout", message, elapsed_ms, timeout_s, tool} — the Ruby work may still be running; call probe to verify state before retrying.',
        inputSchema: {
          type: 'object',
          properties: {
            code:      { type: 'string', description: 'Ruby code to evaluate' },
            op_name:   { type: 'string', description: 'Label for the SketchUp undo operation.', default: 'MCP execute_ruby' },
            wrap_op:   { type: 'boolean', description: 'Wrap the eval in start_operation/commit_operation. Set false for read-only code.', default: true },
            timeout_s: { type: 'integer', description: 'Server-side response-wait timeout (seconds). A timeout does not interrupt the underlying Ruby work; use probe to check state before retrying.', default: 30 }
          },
          required: ['code']
        }
      },
      {
        name: 'execute_ruby_file',
        description: 'Read a Ruby script from an absolute path on the SketchUp host and run it through the same hardened path as execute_ruby. Useful for scripts too large for the transport and for debugging (the file stays on disk). Response shape matches execute_ruby plus {source_file, source_bytes}. Refuses relative paths and files over 1 MB.',
        inputSchema: {
          type: 'object',
          properties: {
            path:      { type: 'string', description: 'Absolute path to a .rb file on the SketchUp host.' },
            op_name:   { type: 'string', description: 'Label for the SketchUp undo operation.', default: 'MCP execute_ruby_file' },
            wrap_op:   { type: 'boolean', default: true },
            timeout_s: { type: 'integer', default: 30 }
          },
          required: ['path']
        }
      },
      {
        name: 'probe',
        description: 'Fast diagnostic read of SketchUp state. Reads a main-thread-refreshed snapshot cache by default, so it responds immediately even when execute_ruby is stuck (a modal dialog, a runaway loop). Pass live=true to route through the main thread for a ground-truth read (pays the wait). Response: {status, title, path, entity_count, active_context, definitions, materials, layers, open_operations, extension_version, fetched_at_ms, snapshot_age_ms, source:"snapshot"|"live"}. A growing snapshot_age_ms is itself the diagnostic that the main thread is blocked.',
        inputSchema: {
          type: 'object',
          properties: {
            live: { type: 'boolean', description: 'Force a main-thread read instead of the snapshot cache.', default: false }
          }
        }
      },
      {
        name: 'create_box',
        description: 'Create a rectangular solid at the given origin with given dimensions (inches). Atomic (wrapped in a SketchUp undo operation; aborted on error). Response: {status, message, origin, size} on success; standard error shape on failure.',
        inputSchema: {
          type: 'object',
          properties: {
            x: { type: 'number', default: 0 },
            y: { type: 'number', default: 0 },
            z: { type: 'number', default: 0 },
            width: { type: 'number' },
            depth: { type: 'number' },
            height: { type: 'number' }
          },
          required: ['width', 'depth', 'height']
        }
      }
    ].freeze

    module_function

    def start(port: DEFAULT_PORT)
      return if running?

      @port = port
      @tcp_server = TCPServer.new('127.0.0.1', port)

      @server_thread = Thread.new do
        Thread.current.abort_on_exception = false
        loop do
          begin
            client = @tcp_server.accept
            Thread.new(client) { |c| handle_connection(c) }
          rescue IOError, Errno::EBADF
            break
          rescue StandardError => e
            puts "[MCP] accept error: #{e.class}: #{e.message}"
          end
        end
      end

      # Pump the main-thread queue every 50ms so model ops run safely
      @main_pump_timer = UI.start_timer(0.05, true) { pump_queue }

      # Seed the snapshot so probe has real data before the first pump tick.
      # start() runs on the main thread (from the menu), so this is safe.
      refresh_snapshot

      puts "[Reentrant SketchUp] MCP server running at http://127.0.0.1:#{port}/mcp"
    rescue Errno::EADDRINUSE
      UI.messagebox("MCP server: port #{port} already in use.")
      @tcp_server = nil
    end

    def stop
      return unless running?

      UI.stop_timer(@main_pump_timer) if @main_pump_timer
      @main_pump_timer = nil

      @tcp_server.close rescue nil
      @tcp_server = nil
      @server_thread.kill rescue nil
      @server_thread = nil
      puts '[Reentrant SketchUp] MCP server stopped'
    end

    def running?
      !@tcp_server.nil? && !@tcp_server.closed?
    end

    def toggle
      running? ? stop : start
    end

    def port
      @port
    end

    # --- HTTP connection handling (background thread) -----------------------

    def handle_connection(client)
      # Support HTTP/1.1 keep-alive: loop reading requests on the same
      # connection until the client closes it or asks to close.
      loop do
        # Wait up to 30s for data; close idle connections.
        ready = IO.select([client], nil, nil, 30)
        break unless ready

        request_line = client.gets
        break if request_line.nil?
        request_line = request_line.chomp
        break if request_line.empty?

        method_name, path, _ = request_line.split(' ', 3)

        headers = {}
        loop do
          line = client.gets
          break if line.nil? || line.chomp.empty?
          k, v = line.chomp.split(': ', 2)
          headers[k.downcase] = v if k && v
        end

        content_length = headers['content-length'].to_i
        body = content_length.positive? ? client.read(content_length) : ''

        close_requested = headers['connection']&.downcase == 'close'

        status, response_body = route(method_name, path, body)
        write_response(client, status, response_body, close_requested)

        break if close_requested
      end
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
      # Client disconnected; nothing to do.
    rescue StandardError => e
      puts "[MCP] connection error: #{e.class}: #{e.message}"
    ensure
      client.close rescue nil
    end

    def write_response(client, status, body, close_conn = false)
      body = body.to_s
      client.write("HTTP/1.1 #{status}\r\n")
      client.write("Content-Type: application/json\r\n")
      client.write("Content-Length: #{body.bytesize}\r\n")
      client.write("Connection: #{close_conn ? 'close' : 'keep-alive'}\r\n")
      client.write("Access-Control-Allow-Origin: *\r\n")
      client.write("Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n")
      client.write("Access-Control-Allow-Headers: Content-Type, Mcp-Session-Id, Accept\r\n")
      client.write("\r\n")
      client.write(body) unless body.empty?
      client.flush
    end

    def route(http_method, path, body)
      return ['404 Not Found', '{}'] unless path&.start_with?('/mcp')

      case http_method
      when 'OPTIONS'
        ['204 No Content', '']
      when 'GET'
        ['405 Method Not Allowed', '']
      when 'POST'
        handle_post(body)
      else
        ['405 Method Not Allowed', '']
      end
    end

    def handle_post(body)
      message = JSON.parse(body) rescue nil
      return ['400 Bad Request', { error: 'invalid JSON' }.to_json] unless message

      # JSON-RPC notifications (no id field) must not have a response body.
      # MCP Streamable HTTP spec says to return 202 Accepted.
      if message['id'].nil?
        dispatch(message)
        return ['202 Accepted', '']
      end

      response = dispatch(message)
      ['200 OK', response ? response.to_json : '']
    end

    def dispatch(message)
      method = message['method']
      id = message['id']
      params = message['params'] || {}

      case method
      when 'initialize'
        {
          jsonrpc: '2.0',
          id: id,
          result: {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: { tools: {} },
            serverInfo: { name: 'reentrant-sketchup', version: PLUGIN_VERSION }
          }
        }
      when 'tools/list'
        { jsonrpc: '2.0', id: id, result: { tools: TOOLS } }
      when 'tools/call'
        name = params['name']
        args = params['arguments'] || {}
        timeout_s = tool_timeout_for(args)
        t0 = Time.now
        payload =
          begin
            if name == 'probe' && !args['live']
              # Snapshot path: worker-thread-only, no main-thread round-trip.
              # This is the escape hatch that works even if execute_ruby is
              # stuck on the main thread.
              read_snapshot_for_probe
            else
              ret = on_main_thread(timeout_s: timeout_s) { call_tool(name, args) }
              if ret == MAIN_THREAD_TIMEOUT
                {
                  status:     'timeout',
                  message:    "Main-thread response-wait exceeded #{timeout_s}s. The Ruby code may still be running; call 'probe' to inspect state before retrying.",
                  elapsed_ms: ((Time.now - t0) * 1000).to_i,
                  timeout_s:  timeout_s,
                  tool:       name
                }
              else
                ret
              end
            end
          rescue StandardError => e
            {
              status:    'error',
              error:     e.class.name,
              message:   e.message.to_s,
              backtrace: (e.backtrace || []).first(8)
            }
          end
        payload = { status: 'ok', result: payload.to_s } unless payload.is_a?(Hash)
        payload[:status] ||= 'ok'
        is_error = %w[error timeout].include?(payload[:status].to_s)
        text = serialize_payload(payload)
        rpc_result = { content: [{ type: 'text', text: text }] }
        rpc_result[:isError] = true if is_error
        { jsonrpc: '2.0', id: id, result: rpc_result }
      when 'ping'
        { jsonrpc: '2.0', id: id, result: {} }
      when 'notifications/initialized'
        nil
      else
        {
          jsonrpc: '2.0',
          id: id,
          error: { code: -32601, message: "Method not found: #{method}" }
        }
      end
    end

    # --- Main-thread marshalling --------------------------------------------

    # Enqueue a block to run on the main thread and wait for its result.
    # Returns the block's value, or MAIN_THREAD_TIMEOUT if the deadline
    # passes first. Does NOT cancel the queued lambda on timeout — the
    # Ruby VM is single-threaded and cannot safely interrupt in-flight
    # SketchUp API calls. Callers should treat a timeout as "the work
    # may still land" and use probe to verify state before retrying.
    def on_main_thread(timeout_s: DEFAULT_TIMEOUT_S, &block)
      mutex = Mutex.new
      cv = ConditionVariable.new
      result = { done: false, value: nil, error: nil }

      @queue_mutex.synchronize do
        @queue << lambda do
          begin
            result[:value] = block.call
          rescue StandardError => e
            result[:error] = e
          end
          mutex.synchronize do
            result[:done] = true
            cv.signal
          end
        end
      end

      deadline = Time.now + timeout_s.to_f
      mutex.synchronize do
        until result[:done]
          remaining = deadline - Time.now
          break if remaining <= 0
          cv.wait(mutex, remaining)
        end
      end

      return MAIN_THREAD_TIMEOUT unless result[:done]
      raise result[:error] if result[:error]
      result[:value]
    end

    def pump_queue
      tasks = nil
      @queue_mutex.synchronize do
        tasks = @queue.dup
        @queue.clear
      end
      tasks.each(&:call)

      @tick_count += 1
      refresh_snapshot if (@tick_count % SNAPSHOT_REFRESH_EVERY_N_TICKS).zero?
    end

    # --- Snapshot cache (read from worker threads, written on main thread) ---

    # Build a fresh snapshot hash and atomically publish it.
    # MUST be called on the main thread (touches the SketchUp API).
    def refresh_snapshot
      model = Sketchup.active_model
      snap =
        if model
          {
            title:             safe_read { model.title },
            path:              safe_read { model.path },
            entity_count:      safe_read { model.entities.count },
            active_context:    safe_read { active_context_label(model) },
            definitions:       safe_read { model.definitions.count },
            materials:         safe_read { model.materials.count },
            layers:            safe_read { model.layers.count },
            open_operations:   @open_operations,
            extension_version: PLUGIN_VERSION,
            fetched_at_ms:     now_ms
          }.freeze
        else
          {
            fetched_at_ms:     now_ms,
            extension_version: PLUGIN_VERSION,
            open_operations:   @open_operations,
            note:              'no active model'
          }.freeze
        end
      @snapshot_mutex.synchronize { @snapshot = snap }
    rescue StandardError => e
      # Leave the prior snapshot in place; record error for diagnostics.
      puts "[MCP] snapshot refresh failed: #{e.class}: #{e.message}"
    end

    # Snapshot read from the worker thread — mutex only, no main-thread wait.
    def read_snapshot_for_probe
      snap = @snapshot_mutex.synchronize { @snapshot }
      decorate_snapshot(snap, 'snapshot')
    end

    # Live read — runs inside on_main_thread, so it also refreshes the cache.
    def tool_probe_live
      refresh_snapshot
      snap = @snapshot_mutex.synchronize { @snapshot }
      decorate_snapshot(snap, 'live')
    end

    def decorate_snapshot(snap, source)
      fetched = snap[:fetched_at_ms]
      age = fetched ? (now_ms - fetched) : nil
      snap.merge(
        status:           snap[:status] || 'ok',
        source:           source,
        snapshot_age_ms:  age
      )
    end

    # Run a block, return its value, or nil on any exception. Used inside the
    # snapshot builder so a single broken accessor doesn't nuke the whole
    # snapshot — we'd rather publish partial data than stall the probe.
    def safe_read
      yield
    rescue StandardError
      nil
    end

    def active_context_label(model)
      path = (model.respond_to?(:active_path) ? model.active_path : nil) || []
      return 'model' if path.empty?
      leaf = path.last
      klass = leaf.class.to_s
      if klass == 'Sketchup::ComponentInstance'
        name = leaf.respond_to?(:definition) ? leaf.definition&.name.to_s : ''
        name.empty? ? 'component' : "component:#{name}"
      elsif klass == 'Sketchup::Group'
        name = leaf.respond_to?(:name) ? leaf.name.to_s : ''
        name.empty? ? 'group' : "group:#{name}"
      else
        "other:#{klass}"
      end
    end

    def now_ms
      (Time.now.to_f * 1000).to_i
    end

    # --- Tool implementations (main thread only) ----------------------------

    def call_tool(name, args)
      case name
      when 'get_selection'     then tool_get_selection
      when 'get_model_info'    then tool_get_model_info
      when 'list_entities'     then tool_list_entities(args['limit'] || 50)
      when 'execute_ruby'      then tool_execute_ruby(args)
      when 'execute_ruby_file' then tool_execute_ruby_file(args)
      when 'probe'             then tool_probe_live  # only reached when live: true
      when 'create_box'        then tool_create_box(args)
      else
        { status: 'error', error: 'UnknownTool', message: "Unknown tool: #{name}" }
      end
    end

    # Resolve the per-call transport timeout. Accepts args['timeout_s'];
    # falls back to DEFAULT_TIMEOUT_S. Clamps to [1, 600] so a buggy
    # client can't pin an HTTP worker thread forever or ship a zero.
    def tool_timeout_for(args)
      raw = args['timeout_s']
      val = raw.nil? ? DEFAULT_TIMEOUT_S : raw.to_i
      val = DEFAULT_TIMEOUT_S if val <= 0
      [[val, 1].max, 600].min
    end

    # Serialize a tool-result hash to a JSON string for the MCP text field.
    # Pretty-printed so humans and LLMs reading the text can skim it. If
    # generation fails (pathological content), fall back to a minimal
    # envelope so the transport still returns something valid.
    def serialize_payload(payload)
      JSON.pretty_generate(payload)
    rescue StandardError => e
      JSON.pretty_generate(
        status:  'error',
        error:   'SerializationFailed',
        message: e.message.to_s
      )
    end

    def tool_get_selection
      model = Sketchup.active_model
      sel = model.selection.to_a
      types = sel.group_by { |e| e.class.to_s.sub('Sketchup::', '') }
                 .transform_values(&:count)
      { status: 'ok', count: sel.length, types: types }
    end

    def tool_get_model_info
      model = Sketchup.active_model
      {
        status:      'ok',
        title:       model.title,
        path:        model.path,
        entities:    model.entities.count,
        definitions: model.definitions.count,
        materials:   model.materials.count,
        layers:      model.layers.count
      }
    end

    def tool_list_entities(limit)
      entities = Sketchup.active_model.active_entities.to_a.first(limit)
      out = entities.map do |e|
        { type: e.class.to_s.sub('Sketchup::', ''), typename: e.typename }
      end
      {
        status:   'ok',
        entities: out,
        total:    Sketchup.active_model.active_entities.count
      }
    end

    def tool_execute_ruby(args)
      code = args['code']
      return bad_arg('code is required') if code.nil? || code.to_s.empty?
      safe_eval(
        code,
        op_name: (args['op_name'] || 'MCP execute_ruby').to_s,
        wrap_op: args.fetch('wrap_op', true)
      )
    end

    def tool_execute_ruby_file(args)
      path    = args['path'].to_s
      op_name = (args['op_name'] || 'MCP execute_ruby_file').to_s
      wrap_op = args.fetch('wrap_op', true)

      return bad_arg('path is required') if path.empty?
      return bad_arg("path must be absolute: #{path}") unless Pathname.new(path).absolute?
      return bad_arg("path not found: #{path}") unless File.file?(path)
      return bad_arg("path not readable: #{path}") unless File.readable?(path)

      size = File.size(path)
      if size > MAX_SCRIPT_FILE_BYTES
        return bad_arg("file too large: #{size} bytes (max #{MAX_SCRIPT_FILE_BYTES})")
      end

      code =
        begin
          File.read(path)
        rescue SystemCallError => e
          return { status: 'error', error: e.class.name, message: e.message.to_s }
        end

      result = safe_eval(code, op_name: op_name, wrap_op: wrap_op)
      result[:source_file] = path
      result[:source_bytes] = size
      result
    end

    def bad_arg(msg)
      { status: 'error', error: 'ArgumentError', message: msg }
    end

    # --- safe_eval --------------------------------------------------------
    #
    # Hardened replacement for raw `eval`. Wraps execution in a SketchUp
    # undo operation by default (atomic-on-error), catches every exception,
    # and returns a structured hash the transport layer can serialize.
    #
    # Intentionally does NOT use `Timeout::timeout`: in SketchUp's Ruby VM
    # the target thread is the main thread, and a timeout cannot interrupt
    # a C-level SketchUp API call (boolean ops, entity iteration, etc.)
    # running inside it. The server-side response-wait timeout (Step 6) is
    # the real backstop; a `timeout` result there does not interrupt the
    # Ruby work, which continues on the main thread.
    #
    # Must be called on the main thread (via on_main_thread).
    def safe_eval(code, op_name: 'MCP Op', wrap_op: true, binding_obj: TOPLEVEL_BINDING)
      t0 = Time.now
      model = Sketchup.active_model
      began_op = false
      begin
        if wrap_op && model
          model.start_operation(op_name, true)
          began_op = true
          @open_operations += 1
        end
        raw = eval(code, binding_obj) # rubocop:disable Security/Eval
        if began_op
          model.commit_operation
          @open_operations -= 1 if @open_operations.positive?
          refresh_snapshot
        end
        result_str =
          begin
            raw.inspect
          rescue StandardError => e
            "<inspect failed: #{e.class}: #{e.message}>"
          end
        {
          status:       'ok',
          result:       truncate_for_transport(result_str),
          result_class: raw.class.name,
          elapsed_ms:   ((Time.now - t0) * 1000).to_i,
          entity_count: (model ? model.entities.count : nil),
          op_name:      op_name
        }
      rescue ScriptError, StandardError => e
        if began_op
          begin
            model.abort_operation
          rescue StandardError
            nil
          end
          @open_operations -= 1 if @open_operations.positive?
        end
        {
          status:     'error',
          error:      e.class.name,
          message:    e.message.to_s,
          backtrace:  (e.backtrace || []).first(8),
          elapsed_ms: ((Time.now - t0) * 1000).to_i,
          op_name:    op_name
        }
      end
    end

    def truncate_for_transport(str, limit = MAX_RESULT_BYTES)
      s = str.to_s
      s = s.dup.force_encoding('UTF-8').scrub('?') unless s.valid_encoding?
      return s if s.bytesize <= limit
      total = s.bytesize
      head = s.byteslice(0, limit).force_encoding('UTF-8').scrub('?')
      "#{head}...[truncated, #{total} total bytes]"
    end

    def open_operations_count
      @open_operations
    end

    def tool_create_box(args)
      x = args['x'] || 0
      y = args['y'] || 0
      z = args['z'] || 0
      w = args['width']
      d = args['depth']
      h = args['height']

      model = Sketchup.active_model
      model.start_operation('MCP Create Box', true)
      @open_operations += 1
      began_op = true
      begin
        group = model.active_entities.add_group
        pts = [
          [x, y, z],
          [x + w, y, z],
          [x + w, y + d, z],
          [x, y + d, z]
        ]
        face = group.entities.add_face(pts)
        face.reverse! if face.normal.z < 0
        face.pushpull(h)
        model.commit_operation
        @open_operations -= 1 if @open_operations.positive?
        began_op = false
        refresh_snapshot
        {
          status:  'ok',
          message: "Created box at [#{x}, #{y}, #{z}] size #{w}x#{d}x#{h}",
          origin:  [x, y, z],
          size:    [w, d, h]
        }
      rescue StandardError => e
        if began_op
          begin
            model.abort_operation
          rescue StandardError
            nil
          end
          @open_operations -= 1 if @open_operations.positive?
        end
        { status: 'error', error: e.class.name, message: e.message.to_s, backtrace: (e.backtrace || []).first(8) }
      end
    end
  end
end
