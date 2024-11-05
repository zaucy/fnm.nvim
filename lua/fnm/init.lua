local last_dir = nil
local is_windows = vim.loop.os_uname().sysname == "Windows_NT"

local M = {}

local function update_env_from_fnm_json(output)
	local success, env_data = pcall(vim.json.decode, output)
	if not success then
		vim.notify('Failed to parse fnm env output: ' .. output, vim.log.levels.ERROR)
		return
	end

	for name, value in pairs(env_data) do
		vim.env[name] = value
	end

	local path_separator = is_windows and ";" or ":"
	local node_bin_path = is_windows and env_data.FNM_MULTISHELL_PATH or (env_data.FNM_MULTISHELL_PATH .. "/bin")
	vim.env.PATH = node_bin_path .. path_separator .. vim.env.PATH
end

local function spawn_fnm()
	local stdout = ''
	local stderr = ''
	local stdout_pipe = vim.uv.new_pipe(false)
	local stderr_pipe = vim.uv.new_pipe(false)

	local handle = vim.uv.spawn('fnm', {
		args = { 'env', '--json' },
		stdio = { nil, stdout_pipe, stderr_pipe },
	}, function(code, _)
		if code ~= 0 then
			vim.notify(
				string.format('fnm exited with code %d: %s', code, stderr),
				vim.log.levels.ERROR
			)
			return
		end

		vim.schedule_wrap(update_env_from_fnm_json)(stdout)
	end)

	if not handle then
		vim.notify('Failed to spawn fnm', vim.log.levels.ERROR)
		return
	end

	vim.uv.read_start(stderr_pipe, function(err, data)
		if err then
			vim.notify('Error reading stderr: ' .. err, vim.log.levels.ERROR)
			return
		end
		if data then
			stderr = stderr .. data
		end
	end)

	vim.uv.read_start(stdout_pipe, function(err, data)
		if err then
			vim.notify('Error reading stdout: ' .. err, vim.log.levels.ERROR)
			return
		end
		if data then
			stdout = stdout .. data
		end
	end)
end


function M.update_fnm_env()
	local current_dir = vim.uv.cwd()
	if last_dir == current_dir then return end

	last_dir = current_dir
	spawn_fnm()
end

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_create_autocmd({ 'DirChanged' }, {
		group = vim.api.nvim_create_augroup('FnmDirChanged', {}),
		callback = function() M.update_fnm_env() end,
	})

	M.update_fnm_env()
end

return M
