let s:configFileName = 'vim-node-config.json' 

function! s:removeSessionKeys(session,...)
	for uvar in a:000
		if has_key(a:session, uvar)
			call remove(a:session, uvar)
		endif
	endfor
endfunction


" configuration defualts, for parameters which might or might not appear in
" the configuration.
function! nodeinspect#config#SetConfigurationDefaults(session)
	let a:session["restart"] = 0
	let a:session["configUsed"] = 0
	let a:session["cwd"] = getcwd()
	let a:session["envFile"] = ""
	let a:session["env"] = ""
endfunction


" replace macros for a string. current recognizable macros (well, one):
" ${workspaceFolder} = pwd
function! s:ReplaceMacros(str)
	let replaced = a:str
	if match(replaced, "${workspaceFolder}") != -1
		let currentDirectory = getcwd()
		let replaced = substitute(a:str,	"${workspaceFolder}", currentDirectory ,"")
	endif
	return replaced
endfunction

" find the config file path. if its not in the currend working directory, try
" going up from the current buffer directory. Returns the directory or empty
" string if failed to find the config file.
function s:GetConfigFilePath()
	let configFilePath = getcwd() . '/' . s:configFileName
	if filereadable(configFilePath)
		return configFilePath
	endif
	" if the file is not found in pwd and the script is a decedant, try going up  
	let expandString = '%:p:h'
	let traverseDir = expand(expandString)
	while stridx(traverseDir, getcwd()) != -1
		let configFilePath = traverseDir . '/' . s:configFileName
		if filereadable(configFilePath)
			return configFilePath
		endif
		let expandString = expandString . ':h'
		let traverseDir = expand(expandString)
	endwhile
	return ''
endfunction



" try and load the config file; it migth not exist, in this case use the
" defaults. returns 0 on success, !0 on failure.
function! nodeinspect#config#LoadConfigFile(session)
	let configuration = {}
	let configFilePath = s:GetConfigFilePath()
	let fullFile = ''
	" clear previous sessoin config
	call s:removeSessionKeys(a:session,"localRoot","remoteRoot")

	if configFilePath != ''
		" indicate this configuration is from file
		let a:session["configUsed"] = 1
		"read file
		let lines = readfile(configFilePath)
		for line in lines
			let fullFile = fullFile . line
		endfor
		" loaded the entire file, parse it to object
		" configPtr holds the used configuration
		let configObj = json_decode(fullFile)
		let configPtr = v:null
		if type(configObj) == v:t_dict 
			" test wherever its a multi configuration
			if has_key(a:session, "configName") == 1 || has_key(configObj,"configurations") == 1
				" validation, the first arg must be present and be the config name
				if len(a:session["args"]) < 1
					echom "Config name must be specified (only it). Use 'args' for paramters"
					return 1
				endif
				" set the config name. other args are irrelevant - should be set from
				" the arg configuration
				let a:session["configName"] = a:session["args"][0]
				if has_key(configObj,"configurations") == 1 && type(configObj["configurations"]) == v:t_list
					" loop over configurations, get the relevant one
					for configItem in configObj["configurations"]
						if type(configItem) == v:t_dict && has_key(configItem, "name") && configItem["name"] == a:session["configName"]
							let configPtr = configItem
							break
						endif
					endfor
				endif
				if type(configPtr) != v:t_dict	
					echom "vim-node-inspect - can't find configuration error"
					return 1
				endif
			else
				let configPtr = configObj
			endif
			if has_key(configPtr,"localRoot") == 1 && has_key(configPtr,"remoteRoot") == 1
				let configuration["localRoot"] = s:ReplaceMacros(configPtr["localRoot"])
				let configuration["remoteRoot"] = configPtr["remoteRoot"]
				" add trailing backslash if not present. it will normalize both inputs
				" in case the user add one with and one without
				if configuration["localRoot"][-1:-1] != '/' 
					let configuration["localRoot"] = configuration["localRoot"] . '/'
				endif
				if configuration["remoteRoot"][-1:-1] != '/' 
					let configuration["remoteRoot"] = configuration["remoteRoot"] . '/'
				endif
			endif
			if has_key(configPtr,"request") == 1
				if configPtr["request"] == 'attach' || configPtr["request"] == 'launch'
					let configuration["request"] = configPtr["request"]
				else
					echom "error reading launch in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"program") == 1
				if type(configPtr["program"]) == 1
					let configuration["program"] = s:ReplaceMacros(configPtr["program"])
				else
					echom "error reading program in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"address") == 1
				if type(configPtr["address"]) == 1
					let configuration["address"] = configPtr["address"]
				else
					echom "error reading address in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"port") == 1
				if type(configPtr["port"]) == 0
					let configuration["port"] = configPtr["port"]
				else
					echom "error reading port in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"restart") == 1
				if configPtr["restart"] == v:true || configPtr["restart"] == 1
					let a:session["restart"] = 1
				else
					let a:session["restart"] = 0
				endif
			endif
			if has_key(configPtr,"cwd") == 1
				if type(configPtr["cwd"]) == 1
					let a:session["cwd"] = s:ReplaceMacros(configPtr["cwd"])
				else
					echom "error reading cwd in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"envFile") == 1
				if type(configPtr["envFile"]) == 1
					let envFile = s:ReplaceMacros(configPtr["envFile"])
					if filereadable(expand(envFile))
						let a:session["envFile"] = envFile
					else
						echom "error reading envfile in vim-node-inspect"
						return 1
					end
				else
					echom "error reading envfile in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configPtr,"env") == 1
				if type(configPtr["env"]) == 4
					let a:session["env"] = json_encode(configPtr["env"])
				else
					echom "error reading envs in vim-node-inspect"
					return 1
				endif
			endif
			" validate config and setup session
			if has_key(configuration, "request") == 1 
				if configuration["request"] == 'attach' 
					if has_key(configuration, "port") == 0
						echom "vim-node-inspect config error, attach without a port"
						return 1
					else
						let a:session["request"] = configuration["request"]
						let a:session["port"] = configuration["port"]
						" address defaults to localhost
						if has_key(configuration, "address")
							let a:session["address"] = configuration["address"]
						else
							let a:session["address"] = "127.0.0.1"
						endif
					endif
				endif
				if configuration["request"] == 'launch' 
					if has_key(configuration, "restart") == 1
						echom "vim-node-inspect config error, restart in invalid in launch mode"
						return 1
					endif
					if has_key(configuration, "program") == 0
						echom "vim-node-inspect config error, launch without a program"
						return 1
					else
						let a:session["request"] = configuration["request"]
						let a:session["script"] = configuration["program"]
					endif
				endif
			endif
			if (has_key(configuration, "localRoot") == 1 || has_key(configuration, "remoteRoot") == 1)
				if ((has_key(configuration, "localRoot") == 1 && has_key(configuration, "remoteRoot") == 0) || (has_key(configuration, "localRoot") == 0 && has_key(configuration, "remoteRoot") == 1))
					echom 'vim-node-inspect directories set error'
					return 1
				else
					let a:session["localRoot"] = configuration["localRoot"]
					let a:session["remoteRoot"] = configuration["remoteRoot"]
				endif
			endif
			" read each line of args in order to alter the value
			let a:session["args"] = []
			if has_key(configPtr,"args") == 1
				for singleArg in configPtr["args"]
					call add(a:session["args"] ,s:ReplaceMacros(singleArg))
				endfor
			endif
		else
			echom 'error reading vim-node-config.json, not a valid json'
			return 1
		endif
	endif
endfunction

