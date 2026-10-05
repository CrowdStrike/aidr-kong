-- Shared `kong`/`ngx`/`resty.http`/`kong.llm.plugin.ctx` stubs for unit-testing
-- kong/plugins/crowdstrike-aidr-shared/ai_guard.lua without a running Kong
-- instance (pongo/docker). Real Kong (and its busted environment) already
-- provides `kong`/`ngx`, so `install()` only needs to fill in the small
-- surface ai_guard.lua actually calls, plus fake out the two Kong-internal
-- modules (resty.http, kong.llm.plugin.ctx) that aren't available outside a
-- real Kong install.
local M = {}

-- Queue of {status, body} (or {err = "..."}) responses returned, in order, by
-- the stubbed resty.http request_uri call. Tests push onto this before
-- exercising code that makes an AIDR HTTP call.
M.http_queue = {}
-- Every {url, opts} the stubbed resty.http client was called with, in order.
M.http_calls = {}

-- Fake backing store for kong.llm.plugin.ctx's shared "_global" ctx
-- (stream_mode, blocked_by_guard, etc.) and per-plugin namespaced ctx
-- (e.g. normalize-sse-chunk's response_model).
M.fake_global_ctx = {}
M.fake_namespaces = {}

function M.reset()
	M.http_queue = {}
	M.http_calls = {}
	M.fake_global_ctx = {}
	M.fake_namespaces = {}
	if kong and kong.ctx then
		kong.ctx.plugin = {}
	end
	if ngx then
		ngx.ctx = {}
		ngx.arg = {}
	end
end

function M.install()
	package.preload["resty.http"] = function()
		return {
			new = function()
				return {
					set_timeout = function() end,
					request_uri = function(_, url, opts)
						table.insert(M.http_calls, { url = url, opts = opts })
						local resp = table.remove(M.http_queue, 1)
						if resp == nil then
							return nil, "no stubbed response queued"
						end
						if resp.err then
							return nil, resp.err
						end
						return { status = resp.status, body = resp.body }, nil
					end,
				}
			end,
		}
	end

	package.preload["kong.llm.plugin.ctx"] = function()
		return {
			get_global_accessors = function()
				return function(key)
					return M.fake_global_ctx[key]
				end
			end,
			has_namespace = function(ns)
				return M.fake_namespaces[ns] ~= nil
			end,
			get_namespaced_ctx = function(ns, key)
				return (M.fake_namespaces[ns] or {})[key]
			end,
		}
	end

	_G.ngx = _G.ngx
		or {
			null = setmetatable({}, {
				__tostring = function()
					return "ngx.null"
				end,
			}),
			ctx = {},
			arg = {},
			timer = {
				-- Run "background" timers synchronously & inline so tests can
				-- observe their effects immediately without a real event loop.
				at = function(_, cb)
					cb(false)
					return true
				end,
			},
		}

	local log_stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})

	_G.kong = _G.kong
		or {
			log = log_stub,
			client = {
				get_consumer = function()
					return nil
				end,
				get_credential = function()
					return nil
				end,
				get_forwarded_ip = function()
					return "127.0.0.1"
				end,
			},
			router = {
				get_service = function()
					return { name = "test-service" }
				end,
			},
			ctx = { plugin = {} },
			request = {
				get_id = function()
					return "req-1"
				end,
			},
			response = {
				get_source = function()
					return "service"
				end,
			},
			service = {
				response = {
					get_status = function()
						return 200
					end,
				},
			},
		}

	M.reset()
end

return M
