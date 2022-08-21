"\ " The functions contained within this file
"\ are for internal use only.
"\ For the official API,
"\ see the commented functions in plugin/fugitive.vim.


if exists('g:autoloaded_fugitive')
    finish
en
let g:autoloaded_fugitive = 1

" Section: Utility

    fun! s:function(name) abort
        return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_'),''))
    endf

    fun! s:sub(str,pat,rep) abort
        return substitute(a:str,'\v\C'.a:pat,a:rep,'')
    endf

    fun! s:gsub(str,pat,rep) abort
        return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
    endf

    fun! s:Uniq(list) abort
        let i = 0
        let seen = {}
        while i < len(a:list)
            let str = string(a:list[i])
            if has_key(seen, str)
                call remove(a:list, i)
            el
                let seen[str] = 1
                let i += 1
            en
        endwhile
        return a:list
    endf

    fun! s:JoinChomp(list) abort
        if empty(a:list[-1])
            return join(a:list[0:-2], "\n")
        el
            return join(a:list, "\n")
        en
    endf

    fun! s:winshell() abort
        return has('win32') && &shellcmdflag !~# '^-'
    endf

    fun! s:WinShellEsc(arg) abort
        if type(a:arg) == type([])
            return join(map(copy(a:arg), 's:WinShellEsc(v:val)'))
        elseif a:arg =~# '^[A-Za-z0-9_/:.-]\+$'
            return a:arg
        el
            return '"' . s:gsub(s:gsub(a:arg, '"', '""'), '\%', '"%"') . '"'
        en
    endf

    fun! s:shellesc(arg) abort
        if type(a:arg) == type([])
            return join(map(copy(a:arg), 's:shellesc(v:val)'))
        elseif a:arg =~# '^[A-Za-z0-9_/:.-]\+$'
            return a:arg
        elseif s:winshell()
            return '"' . s:gsub(s:gsub(a:arg, '"', '""'), '\%', '"%"') . '"'
        el
            return shellescape(a:arg)
        en
    endf

    let s:fnameescape = " \t\n*?[{`$\\%#'\"|!<"
    fun! s:fnameescape(file) abort
        if type(a:file) == type([])
            return join(map(copy(a:file), 's:fnameescape(v:val)'))
        elseif exists('*fnameescape')
            return fnameescape(a:file)
        el
            return escape(a:file, s:fnameescape)
        en
    endf

    fun! s:throw(string) abort
        throw 'fugitive: '.a:string
    endf

    fun! s:VersionCheck() abort
        if v:version < 703
            return 'return ' . string('echoerr "fugitive: Vim 7.3 or newer required"')
        elseif empty(fugitive#GitVersion())
            let exe = get(s:GitCmd(), 0, '')
            if len(exe) && !executable(exe)
                return 'return ' . string('echoerr "fugitive: cannot find ' . string(exe) . ' in PATH"')
            en
            return 'return ' . string('echoerr "fugitive: cannot execute Git"')
        elseif !fugitive#GitVersion(1, 8, 5)
            return 'return ' . string('echoerr "fugitive: Git 1.8.5 or newer required"')
        el
            return ''
        en
    endf

    let s:worktree_error = "core.worktree is required when using an external Git dir"
    fun! s:DirCheck(...) abort
        let vcheck = s:VersionCheck()
        if !empty(vcheck)
            return vcheck
        en
        let dir = call('FugitiveGitDir', a:000)
        if !empty(dir) && FugitiveWorkTree(dir, 1) is# 0
            return 'return ' . string('echoerr "fugitive: ' . s:worktree_error . '"')
        elseif !empty(dir)
            return ''
        elseif empty(bufname(''))
            return 'return ' . string('echoerr "fugitive: working directory does not belong to a Git repository"')
        el
            return 'return ' . string('echoerr "fugitive: file does not belong to a Git repository"')
        en
    endf

    fun! s:Mods(mods, ...) abort
        let mods = substitute(a:mods, '\C<mods>', '', '')
        let mods = mods =~# '\S$' ? mods . ' ' : mods
        if a:0 && mods !~# '\<\%(aboveleft\|belowright\|leftabove\|rightbelow\|topleft\|botright\|tab\)\>'
            if a:1 ==# 'Edge'
                if mods =~# '\<vertical\>' ? &splitright : &splitbelow
                    let mods = 'botright ' . mods
                el
                    let mods = 'topleft ' . mods
                en
            el
                let mods = a:1 . ' ' . mods
            en
        en
        return substitute(mods, '\s\+', ' ', 'g')
    endf

    if exists('+shellslash')
        fun! s:Slash(path) abort
            return tr(a:path, '\', '/')
        endf
    el
        fun! s:Slash(path) abort
            return a:path
        endf
    en

    fun! s:AbsoluteVimPath(...) abort
        if a:0 && type(a:1) == type('')
            let path = a:1
        el
            let path = bufname(a:0 && a:1 > 0 ? a:1 : '')
            if getbufvar(a:0 && a:1 > 0 ? a:1 : '', '&buftype') !~# '^\%(nowrite\|acwrite\)\=$'
                return path
            en
        en
        if s:Slash(path) =~# '^/\|^\a\+:'
            return path
        el
            return getcwd() . matchstr(getcwd(), '[\\/]') . path
        en
    endf

    fun! s:Resolve(path) abort
        let path = resolve(a:path)
        if has('win32')
            let path = FugitiveVimPath(fnamemodify(fnamemodify(path, ':h'), ':p') . fnamemodify(path, ':t'))
        en
        return path
    endf

    fun! s:FileIgnoreCase(for_completion) abort
        return (exists('+fileignorecase') && &fileignorecase)
                    \ || (a:for_completion && exists('+wildignorecase') && &wildignorecase)
    endf

    fun! s:cpath(path, ...) abort
        if s:FileIgnoreCase(0)
            let path = FugitiveVimPath(tolower(a:path))
        el
            let path = FugitiveVimPath(a:path)
        en
        return a:0 ? path ==# s:cpath(a:1) : path
    endf

    let s:executables = {}

    fun! s:executable(binary) abort
        if !has_key(s:executables, a:binary)
            let s:executables[a:binary] = executable(a:binary)
        en
        return s:executables[a:binary]
    endf

    if !exists('s:temp_scripts')
        let s:temp_scripts = {}
    en
    fun! s:TempScript(...) abort
        let body = join(a:000, "\n")
        if !has_key(s:temp_scripts, body)
            let s:temp_scripts[body] = tempname() . '.sh'
        en
        let temp = s:temp_scripts[body]
        if !filereadable(temp)
            call writefile(['#!/bin/sh'] + a:000, temp)
        en
        return FugitiveGitPath(temp)
    endf

    fun! s:DoAutocmd(...) abort
        if v:version >= 704 || (v:version == 703 && has('patch442'))
            return join(map(copy(a:000), "'doautocmd <nomodeline>' . v:val"), '|')
        elseif &modelines > 0
            return 'try|set modelines=0|' . join(map(copy(a:000), "'doautocmd ' . v:val"), '|') . '|finally|set modelines=' . &modelines . '|endtry'
        el
            return join(map(copy(a:000), "'doautocmd ' . v:val"), '|')
        en
    endf

    let s:nowait = v:version >= 704 ? '<nowait>' : ''

    fun! s:Map(mode, lhs, rhs, ...) abort
        let maps = []
        let defer = a:0 && a:1 =~# '<unique>' || get(g:, 'fugitive_defer_to_existing_maps')
        let flags = substitute(a:0 ? a:1 : '', '<unique>', '', '') . (a:rhs =~# '<Plug>' ? '' : '<script>') . s:nowait
        for mode in split(a:mode, '\zs')
            if a:0 <= 1
                call add(maps, mode.'map <buffer>' . substitute(flags, '<unique>', '', '') . ' <Plug>fugitive:' . a:lhs . ' ' . a:rhs)
            en
            let skip = 0
            let head = a:lhs
            let tail = ''
            let keys = get(g:, mode.'remap', {})
            if type(keys) == type([])
                continue
            en
            while !empty(head)
                if has_key(keys, head)
                    let head = keys[head]
                    let skip = empty(head)
                    break
                en
                let tail = matchstr(head, '<[^<>]*>$\|.$') . tail
                let head = substitute(head, '<[^<>]*>$\|.$', '', '')
            endwhile
            if !skip && (!defer || empty(mapcheck(head.tail, mode)))
                call add(maps, mode.'map <buffer>' . flags . ' ' . head.tail . ' ' . a:rhs)
                if a:0 > 1 && a:2
                    let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') .
                                \ '|sil! exe "' . mode . 'unmap <buffer> ' . head.tail . '"'
                en
            en
        endfor
        exe join(maps, '|')
        return ''
    endf

    fun! fugitive#Autowrite() abort
        if &autowrite || &autowriteall
            try
                if &confirm
                    let reconfirm = 1
                    setglobal noconfirm
                en
                silent! wall
            finally
                if exists('reconfirm')
                    setglobal confirm
                en
            endtry
        en
        return ''
    endf

    fun! fugitive#Wait(job_or_jobs, ...) abort
        let original = type(a:job_or_jobs) == type([]) ? copy(a:job_or_jobs) : [a:job_or_jobs]
        let jobs = map(copy(original), 'type(v:val) ==# type({}) ? get(v:val, "job", "") : v:val')
        call filter(jobs, 'type(v:val) !=# type("")')
        let timeout_ms = a:0 ? a:1 : -1
        if exists('*jobwait')
            call map(copy(jobs), 'chanclose(v:val, "stdin")')
            call jobwait(jobs, timeout_ms)
            let jobs = map(copy(original), 'type(v:val) ==# type({}) ? get(v:val, "job", "") : v:val')
            call filter(jobs, 'type(v:val) !=# type("")')
            if len(jobs)
                sleep 1m
            en
        el
            let sleep = has('patch-8.2.2366') ? 'sleep! 1m' : 'sleep 1m'
            for job in jobs
                if ch_status(job) !=# 'closed'
                    call ch_close_in(job)
                en
            endfor
            let i = 0
            for job in jobs
                while ch_status(job) !=# 'closed' || job_status(job) ==# 'run'
                    if i == timeout_ms
                        break
                    en
                    let i += 1
                    exe sleep
                endwhile
            endfor
        en
        return a:job_or_jobs
    endf

    fun! s:JobVimExit(dict, callback, temp, job, status) abort
        let a:dict.exit_status = a:status
        let a:dict.stderr = readfile(a:temp . '.err', 'b')
        call delete(a:temp . '.err')
        let a:dict.stdout = readfile(a:temp . '.out', 'b')
        call delete(a:temp . '.out')
        call delete(a:temp . '.in')
        call remove(a:dict, 'job')
        call call(a:callback[0], [a:dict] + a:callback[1:-1])
    endf

    fun! s:JobNvimExit(dict, callback, job, data, type) dict abort
        let a:dict.stdout = self.stdout
        let a:dict.stderr = self.stderr
        let a:dict.exit_status = a:data
        call remove(a:dict, 'job')
        call call(a:callback[0], [a:dict] + a:callback[1:-1])
    endf

    fun! s:JobExecute(argv, jopts, stdin, callback, ...) abort
        let dict = a:0 ? a:1 : {}
        let cb = len(a:callback) ? a:callback : [function('len')]
        if exists('*jobstart')
            call extend(a:jopts, {
                        \ 'stdout_buffered': v:true,
                        \ 'stderr_buffered': v:true,
                        \ 'on_exit': function('s:JobNvimExit', [dict, cb])})
            let dict.job = jobstart(a:argv, a:jopts)
            if !empty(a:stdin)
                call chansend(dict.job, a:stdin)
                call chanclose(dict.job, 'stdin')
            en
        elseif exists('*ch_close_in')
            let temp = tempname()
            call extend(a:jopts, {
                        \ 'out_io': 'file',
                        \ 'out_name': temp . '.out',
                        \ 'err_io': 'file',
                        \ 'err_name': temp . '.err',
                        \ 'exit_cb': function('s:JobVimExit', [dict, cb, temp])})
            if a:stdin ==# ['']
                let a:jopts.in_io = 'null'
            elseif !empty(a:stdin)
                let a:jopts.in_io = 'file'
                let a:jopts.in_name = temp . '.in'
                call writefile(a:stdin, a:jopts.in_name, 'b')
            en
            let dict.job = job_start(a:argv, a:jopts)
        elseif &shell !~# 'sh' || &shell =~# 'fish\|\%(powershell\|pwsh\)\%(\.exe\)\=$'
            throw 'fugitive: Vim 8 or higher required to use ' . &shell
        el
            let cmd = s:shellesc(a:argv)
            let outfile = tempname()
            try
                if len(a:stdin)
                    call writefile(a:stdin, outfile . '.in', 'b')
                    let cmd = ' (' . cmd . ' >' . outfile . ' <' . outfile . '.in) '
                el
                    let cmd = ' (' . cmd . ' >' . outfile . ') '
                en
                let dict.stderr = split(system(cmd), "\n", 1)
                let dict.exit_status = v:shell_error
                let dict.stdout = readfile(outfile, 'b')
                call call(cb[0], [dict] + cb[1:-1])
            finally
                call delete(outfile)
                call delete(outfile . '.in')
            endtry
        en
        if empty(a:callback)
            call fugitive#Wait(dict)
        en
        return dict
    endf

    fun! s:add_methods(namespace, method_names) abort
        for name in a:method_names
            let s:{a:namespace}_prototype[name] = s:function('s:'.a:namespace.'_'.name)
        endfor
    endf

" Section: Git

    let s:run_jobs = (exists('*ch_close_in') || exists('*jobstart')) && exists('*bufwinid')

    fun! s:GitCmd() abort
        if !exists('g:fugitive_git_executable')
            return ['git']
        elseif type(g:fugitive_git_executable) == type([])
            return g:fugitive_git_executable
        el
            let dquote = '"\%([^"]\|""\|\\"\)*"\|'
            let string = g:fugitive_git_executable
            let list = []
            if string =~# '^\w\+='
                call add(list, '/usr/bin/env')
            en
            while string =~# '\S'
                let arg = matchstr(string, '^\s*\%(' . dquote . '''[^'']*''\|\\.\|[^[:space:] |]\)\+')
                let string = strpart(string, len(arg))
                let arg = substitute(arg, '^\s\+', '', '')
                let arg = substitute(arg,
                            \ '\(' . dquote . '''\%(''''\|[^'']\)*''\|\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\)\|' . s:expand,
                            \ '\=submatch(0)[0] ==# "\\" ? submatch(0)[1] : submatch(0)[1:-2]', 'g')
                call add(list, arg)
            endwhile
            return list
        en
    endf

    fun! s:GitShellCmd() abort
        if !exists('g:fugitive_git_executable')
            return 'git'
        elseif type(g:fugitive_git_executable) == type([])
            return s:shellesc(g:fugitive_git_executable)
        el
            return g:fugitive_git_executable
        en
    endf

    fun! s:UserCommandCwd(dir) abort
        let tree = s:Tree(a:dir)
        return len(tree) ? FugitiveVimPath(tree) : getcwd()
    endf

    fun! s:UserCommandList(...) abort
        if !fugitive#GitVersion(1, 8, 5)
            throw 'fugitive: Git 1.8.5 or higher required'
        en
        if !exists('g:fugitive_git_command')
            let git = s:GitCmd()
        elseif type(g:fugitive_git_command) == type([])
            let git = g:fugitive_git_command
        el
            let git = split(g:fugitive_git_command, '\s\+')
        en
        let flags = []
        if a:0 && type(a:1) == type({})
            let git = copy(get(a:1, 'git', git))
            let flags = get(a:1, 'flags', flags)
            let dir = a:1.git_dir
        elseif a:0
            let dir = s:GitDir(a:1)
        el
            let dir = ''
        en
        if len(dir)
            let tree = s:Tree(dir)
            if empty(tree)
                call add(git, '--git-dir=' . FugitiveGitPath(dir))
            el
                if !s:cpath(tree . '/.git', dir) || len($GIT_DIR)
                    call add(git, '--git-dir=' . FugitiveGitPath(dir))
                en
                if !s:cpath(tree, getcwd())
                    call extend(git, ['-C', FugitiveGitPath(tree)])
                en
            en
        en
        return git + flags
    endf

    let s:git_versions = {}
    fun! fugitive#GitVersion(...) abort
        let git = s:GitShellCmd()
        if !has_key(s:git_versions, git)
            let s:git_versions[git] = matchstr(get(s:JobExecute(s:GitCmd() + ['--version'], {}, [], [], {}).stdout, 0, ''), '\d[^[:space:]]\+')
        en
        if !a:0
            return s:git_versions[git]
        en
        let components = split(s:git_versions[git], '\D\+')
        if empty(components)
            return -1
        en
        for i in range(len(a:000))
            if a:000[i] > +get(components, i)
                return 0
            elseif a:000[i] < +get(components, i)
                return 1
            en
        endfor
        return a:000[i] ==# get(components, i)
    endf

    fun! s:Dir(...) abort
        return a:0 ? FugitiveGitDir(a:1) : FugitiveGitDir()
    endf

    fun! s:GitDir(...) abort
        return a:0 ? FugitiveGitDir(a:1) : FugitiveGitDir()
    endf

    fun! s:DirUrlPrefix(...) abort
        return 'fugitive://' . call('s:GitDir', a:000) . '//'
    endf

    fun! s:Tree(...) abort
        return a:0 ? FugitiveWorkTree(a:1) : FugitiveWorkTree()
    endf

    fun! s:HasOpt(args, ...) abort
        let args = a:args[0 : index(a:args, '--')]
        let opts = copy(a:000)
        if type(opts[0]) == type([])
            if empty(args) || index(opts[0], args[0]) == -1
                return 0
            en
            call remove(opts, 0)
        en
        for opt in opts
            if index(args, opt) != -1
                return 1
            en
        endfor
    endf

    fun! s:PreparePathArgs(cmd, dir, literal, explicit) abort
        if !a:explicit
            call insert(a:cmd, '--literal-pathspecs')
        en
        let split = index(a:cmd, '--')
        for i in range(split < 0 ? len(a:cmd) : split)
                if type(a:cmd[i]) == type(0)
                    if a:literal
                        let a:cmd[i] = fugitive#Path(bufname(a:cmd[i]), './', a:dir)
                    el
                        let a:cmd[i] = fugitive#Path(bufname(a:cmd[i]), ':(top,literal)', a:dir)
                    en
                en
        endfor
        if split < 0
            return a:cmd
        en
        for i in range(split + 1, len(a:cmd) - 1)
            if type(a:cmd[i]) == type(0)
                if a:literal
                    let a:cmd[i] = fugitive#Path(bufname(a:cmd[i]), './', a:dir)
                el
                    let a:cmd[i] = fugitive#Path(bufname(a:cmd[i]), ':(top,literal)', a:dir)
                en
            elseif !a:explicit
                let a:cmd[i] = fugitive#Path(a:cmd[i], './', a:dir)
            en
        endfor
        return a:cmd
    endf

    fun! s:PrepareEnv(env, dir) abort
        if len($GIT_INDEX_FILE)
        \ && len(s:Tree(a:dir))
        \ && !has_key(a:env, 'GIT_INDEX_FILE')
            let index_dir = substitute($GIT_INDEX_FILE, '[^/]\+$', '', '')
            let our_dir = fugitive#Find('.git/', a:dir)
            if !s:cpath(index_dir, our_dir)
            \ && !s:cpath(resolve(FugitiveVimPath(index_dir)), our_dir)
                let a:env['GIT_INDEX_FILE'] = FugitiveGitPath(fugitive#Find('.git/index', a:dir))
            en
        en

        if len($GIT_WORK_TREE)
            let a:env['GIT_WORK_TREE'] = '.'
        en
    endf

    let s:prepare_env = {
                \ 'sequence.editor': 'GIT_SEQUENCE_EDITOR',
                \ 'core.editor': 'GIT_EDITOR',
                \ 'core.askpass': 'GIT_ASKPASS',
                \ }
    fun! fugitive#PrepareDirEnvGitFlagsArgs(...) abort
        if !fugitive#GitVersion(1, 8, 5)
            throw 'fugitive: Git 1.8.5 or higher required'
        en
        let git = s:GitCmd()
        if a:0 == 1 && type(a:1) == type({}) && has_key(a:1, 'git_dir') && has_key(a:1, 'flags') && has_key(a:1, 'args')
            let cmd = a:1.flags + a:1.args
            let dir = a:1.git_dir
            if has_key(a:1, 'git')
                let git = a:1.git
            en
            let env = get(a:1, 'env', {})
        el
            let list_args = []
            let cmd = []
            for arg in a:000
                if type(arg) ==# type([])
                    call extend(list_args, arg)
                el
                    call add(cmd, arg)
                en
            endfor
            call extend(cmd, list_args)
            let env = {}
        en
        let autoenv = {}
        let explicit_pathspec_option = 0
        let literal_pathspecs = 1
        let i = 0
        let arg_count = 0
        while i < len(cmd)
            if type(cmd[i]) == type({})
                if has_key(cmd[i], 'git_dir')
                    let dir = cmd[i].git_dir
                elseif has_key(cmd[i], 'dir')
                    let dir = cmd[i].dir
                en
                if has_key(cmd[i], 'git')
                    let git = cmd[i].git
                en
                if has_key(cmd[i], 'env')
                    call extend(env, cmd[i].env)
                en
                call remove(cmd, i)
            elseif cmd[i] =~# '^$\|[\/.]' && cmd[i] !~# '^-'
                let dir = remove(cmd, i)
            elseif cmd[i] =~# '^--git-dir='
                let dir = remove(cmd, i)[10:-1]
            elseif type(cmd[i]) ==# type(0)
                let dir = s:Dir(remove(cmd, i))
            elseif cmd[i] ==# '-c' && len(cmd) > i + 1
                let key = matchstr(cmd[i+1], '^[^=]*')
                if has_key(s:prepare_env, tolower(key))
                    let var = s:prepare_env[tolower(key)]
                    let val = matchstr(cmd[i+1], '=\zs.*')
                    let autoenv[var] = val
                en
                let i += 2
            elseif cmd[i] =~# '^--.*pathspecs$'
                let literal_pathspecs = (cmd[i] ==# '--literal-pathspecs')
                let explicit_pathspec_option = 1
                let i += 1
            elseif cmd[i] !~# '^-'
                let arg_count = len(cmd) - i
                break
            el
                let i += 1
            en
        endwhile
        if !exists('dir')
            let dir = s:Dir()
        en
        call extend(autoenv, env)
        call s:PrepareEnv(autoenv, dir)
        if len($GPG_TTY) && !has_key(autoenv, 'GPG_TTY')
            let autoenv.GPG_TTY = ''
        en
        call s:PreparePathArgs(cmd, dir, literal_pathspecs, explicit_pathspec_option)
        return [s:GitDir(dir), env, extend(autoenv, env), git, cmd[0 : -arg_count-1], arg_count ? cmd[-arg_count : -1] : []]
    endf

    fun! s:BuildEnvPrefix(env) abort
        let pre = ''
        let env = items(a:env)
        if empty(env)
            return ''
        elseif &shell =~# '\%(powershell\|pwsh\)\%(\.exe\)\=$'
            return join(map(env, '"$Env:" . v:val[0] . " = ''" . substitute(v:val[1], "''", "''''", "g") . "''; "'), '')
        elseif s:winshell()
            return join(map(env, '"set " . substitute(join(v:val, "="), "[&|<>^]", "^^^&", "g") . "& "'), '')
        el
            return '/usr/bin/env ' . s:shellesc(map(env, 'join(v:val, "=")')) . ' '
        en
    endf

    fun! s:JobOpts(cmd, env) abort
        if empty(a:env)
            return [a:cmd, {}]
        elseif has('patch-8.2.0239') ||
                    \ has('nvim') && api_info().version.api_level - api_info().version.api_prerelease >= 7 ||
                    \ has('patch-8.0.0902') && !has('nvim') && (!has('win32') || empty(filter(keys(a:env), 'exists("$" . v:val)')))
            return [a:cmd, {'env': a:env}]
        en
        let envlist = map(items(a:env), 'join(v:val, "=")')
        if !has('win32')
            return [['/usr/bin/env'] + envlist + a:cmd, {}]
        el
            let pre = join(map(envlist, '"set " . substitute(v:val, "[&|<>^]", "^^^&", "g") . "& "'), '')
            if len(a:cmd) == 3 && a:cmd[0] ==# 'cmd.exe' && a:cmd[1] ==# '/c'
                return [a:cmd[0:1] + [pre . a:cmd[2]], {}]
            el
                return [['cmd.exe', '/c', pre . s:WinShellEsc(a:cmd)], {}]
            en
        en
    endf

    fun! s:PrepareJob(opts) abort
        let dict = {'argv': a:opts.argv}
        if has_key(a:opts, 'env')
            let dict.env = a:opts.env
        en
        let [argv, jopts] = s:JobOpts(a:opts.argv, get(a:opts, 'env', {}))
        if has_key(a:opts, 'cwd')
            if has('patch-8.0.0902')
                let jopts.cwd = a:opts.cwd
                let dict.cwd = a:opts.cwd
            el
                throw 'fugitive: cwd unsupported'
            en
        en
        return [argv, jopts, dict]
    endf

    fun! fugitive#PrepareJob(...) abort
        if a:0 == 1 && type(a:1) == type({}) && has_key(a:1, 'argv') && !has_key(a:1, 'args')
            return s:PrepareJob(a:1)
        en
        let [dir, user_env, exec_env, git, flags, args] = call('fugitive#PrepareDirEnvGitFlagsArgs', a:000)
        let dict = {'git': git, 'git_dir': dir, 'flags': flags, 'args': args}
        if len(user_env)
            let dict.env = user_env
        en
        let cmd = flags + args
        let tree = s:Tree(dir)
        if empty(tree) || index(cmd, '--') == len(cmd) - 1
            let dict.cwd = getcwd()
            call extend(cmd, ['--git-dir=' . FugitiveGitPath(dir)], 'keep')
        el
            let dict.cwd = FugitiveVimPath(tree)
            call extend(cmd, ['-C', FugitiveGitPath(tree)], 'keep')
            if !s:cpath(tree . '/.git', dir) || len($GIT_DIR)
                call extend(cmd, ['--git-dir=' . FugitiveGitPath(dir)], 'keep')
            en
        en
        call extend(cmd, git, 'keep')
        return s:JobOpts(cmd, exec_env) + [dict]
    endf

    fun! fugitive#Execute(...) abort
        let cb = copy(a:000)
        let cmd = []
        let stdin = []
        while len(cb) && type(cb[0]) !=# type(function('tr'))
            if type(cb[0]) ==# type({}) && has_key(cb[0], 'stdin')
                if type(cb[0].stdin) == type([])
                    call extend(stdin, cb[0].stdin)
                elseif type(cb[0].stdin) == type('')
                    call extend(stdin, readfile(cb[0].stdin, 'b'))
                en
                if len(keys(cb[0])) == 1
                    call remove(cb, 0)
                    continue
                en
            en
            call add(cmd, remove(cb, 0))
        endwhile
        let [argv, jopts, dict] = call('fugitive#PrepareJob', cmd)
        return s:JobExecute(argv, jopts, stdin, cb, dict)
    endf

    fun! s:BuildShell(dir, env, git, args) abort
        let cmd = copy(a:args)
        let tree = s:Tree(a:dir)
        let pre = s:BuildEnvPrefix(a:env)
        if empty(tree) || index(cmd, '--') == len(cmd) - 1
            call insert(cmd, '--git-dir=' . FugitiveGitPath(a:dir))
        el
            call extend(cmd, ['-C', FugitiveGitPath(tree)], 'keep')
            if !s:cpath(tree . '/.git', a:dir) || len($GIT_DIR)
                call extend(cmd, ['--git-dir=' . FugitiveGitPath(a:dir)], 'keep')
            en
        en
        return pre . join(map(a:git + cmd, 's:shellesc(v:val)'))
    endf

    fun! s:JobNvimCallback(lines, job, data, type) abort
        let a:lines[-1] .= remove(a:data, 0)
        call extend(a:lines, a:data)
    endf

    fun! s:SystemList(cmd) abort
        let exit = []
        if exists('*jobstart')
            let lines = ['']
            let jopts = {
                        \ 'on_stdout': function('s:JobNvimCallback', [lines]),
                        \ 'on_stderr': function('s:JobNvimCallback', [lines]),
                        \ 'on_exit': { j, code, _ -> add(exit, code) }}
            let job = jobstart(a:cmd, jopts)
            call chanclose(job, 'stdin')
            call jobwait([job])
            if empty(lines[-1])
                call remove(lines, -1)
            en
            return [lines, exit[0]]
        elseif exists('*ch_close_in')
            let lines = []
            let jopts = {
                        \ 'out_cb': { j, str -> add(lines, str) },
                        \ 'err_cb': { j, str -> add(lines, str) },
                        \ 'exit_cb': { j, code -> add(exit, code) }}
            let job = job_start(a:cmd, jopts)
            call ch_close_in(job)
            let sleep = has('patch-8.2.2366') ? 'sleep! 1m' : 'sleep 1m'
            while ch_status(job) !=# 'closed' || job_status(job) ==# 'run'
                exe sleep
            endwhile
            return [lines, exit[0]]
        el
            let [output, exec_error] = s:SystemError(s:shellesc(a:cmd))
            let lines = split(output, "\n", 1)
            if empty(lines[-1])
                call remove(lines, -1)
            en
            return [lines, v:shell_error]
        en
    endf

    fun! fugitive#ShellCommand(...) abort
        let [dir, _, env, git, flags, args] = call('fugitive#PrepareDirEnvGitFlagsArgs', a:000)
        return s:BuildShell(dir, env, git, flags + args)
    endf

    fun! fugitive#Prepare(...) abort
        return call('fugitive#ShellCommand', a:000)
    endf

    fun! s:SystemError(cmd, ...) abort
        let cmd = type(a:cmd) == type([]) ? s:shellesc(a:cmd) : a:cmd
        try
            if &shellredir ==# '>' && &shell =~# 'sh\|cmd'
                let shellredir = &shellredir
                if &shell =~# 'csh'
                    set shellredir=>&
                el
                    set shellredir=>%s\ 2>&1
                en
            en
            if exists('+guioptions') && &guioptions =~# '!'
                let guioptions = &guioptions
                set guioptions-=!
            en
            let out = call('system', [cmd] + a:000)
            return [out, v:shell_error]
        catch /^Vim\%((\a\+)\)\=:E484:/
            let opts = ['shell', 'shellcmdflag', 'shellredir', 'shellquote', 'shellxquote', 'shellxescape', 'shellslash']
            call filter(opts, 'exists("+".v:val) && !empty(eval("&".v:val))')
            call map(opts, 'v:val."=".eval("&".v:val)')
            call s:throw('failed to run `' . cmd . '` with ' . join(opts, ' '))
        finally
            if exists('shellredir')
                let &shellredir = shellredir
            en
            if exists('guioptions')
                let &guioptions = guioptions
            en
        endtry
    endf

    fun! s:ChompStderr(...) abort
        let r = call('fugitive#Execute', a:000)
        return !r.exit_status ? '' : len(r.stderr) > 1 ? s:JoinChomp(r.stderr) : 'unknown Git error' . string(r)
    endf

    fun! s:ChompDefault(default, ...) abort
        let r = call('fugitive#Execute', a:000)
        return r.exit_status ? a:default : s:JoinChomp(r.stdout)
    endf

    fun! s:LinesError(...) abort
        let r = call('fugitive#Execute', a:000)
        if empty(r.stdout[-1])
            call remove(r.stdout, -1)
        en
        return [r.exit_status ? [] : r.stdout, r.exit_status]
    endf

    fun! s:NullError(cmd) abort
        let r = fugitive#Execute(a:cmd)
        let list = r.exit_status ? [] : split(tr(join(r.stdout, "\1"), "\1\n", "\n\1"), "\1", 1)[0:-2]
        return [list, s:JoinChomp(r.stderr), r.exit_status]
    endf

    fun! s:TreeChomp(...) abort
        let r = call('fugitive#Execute', a:000)
        if !r.exit_status
            return s:JoinChomp(r.stdout)
        en
        throw 'fugitive: error running `' . call('fugitive#ShellCommand', a:000) . '`: ' . s:JoinChomp(r.stderr)
    endf

    fun! s:StdoutToFile(out, cmd, ...) abort
        let [argv, jopts, _] = fugitive#PrepareJob(a:cmd)
        let exit = []
        if exists('*jobstart')
            call extend(jopts, {
                        \ 'stdout_buffered': v:true,
                        \ 'stderr_buffered': v:true,
                        \ 'on_exit': { j, code, _ -> add(exit, code) }})
            let job = jobstart(argv, jopts)
            if a:0
                call chansend(job, a:1)
            en
            call chanclose(job, 'stdin')
            call jobwait([job])
            if len(a:out)
                call writefile(jopts.stdout, a:out, 'b')
            en
            return [join(jopts.stderr, "\n"), exit[0]]
        elseif exists('*ch_close_in')
            try
                let err = tempname()
                call extend(jopts, {
                            \ 'out_io': len(a:out) ? 'file' : 'null',
                            \ 'out_name': a:out,
                            \ 'err_io': 'file',
                            \ 'err_name': err,
                            \ 'exit_cb': { j, code -> add(exit, code) }})
                let job = job_start(argv, jopts)
                if a:0
                    call ch_sendraw(job, a:1)
                en
                call ch_close_in(job)
                while ch_status(job) !=# 'closed' || job_status(job) ==# 'run'
                    exe has('patch-8.2.2366') ? 'sleep! 1m' : 'sleep 1m'
                endwhile
                return [join(readfile(err, 'b'), "\n"), exit[0]]
            finally
                call delete(err)
            endtry
        elseif s:winshell() || &shell !~# 'sh' || &shell =~# 'fish\|\%(powershell\|pwsh\)\%(\.exe\)\=$'
            throw 'fugitive: Vim 8 or higher required to use ' . &shell
        el
            let cmd = fugitive#ShellCommand(a:cmd)
            return s:SystemError(' (' . cmd . ' >' . a:out . ') ')
        en
    endf

    let s:head_cache = {}

    fun! fugitive#Head(...) abort
        let dir = a:0 > 1 ? a:2 : s:Dir()
        if empty(dir)
            return ''
        en
        let file = fugitive#Find('.git/HEAD', dir)
        let ftime = getftime(file)
        if ftime == -1
            return ''
        elseif ftime != get(s:head_cache, file, [-1])[0]
            let s:head_cache[file] = [ftime, readfile(file)[0]]
        en
        let head = s:head_cache[file][1]
        let len = a:0 ? a:1 : 0
        if head =~# '^ref: '
            if len < 0
                return strpart(head, 5)
            el
                return substitute(head, '\C^ref: \%(refs/\%(heads/\|remotes/\|tags/\)\=\)\=', '', '')
            en
        elseif head =~# '^\x\{40,\}$'
            return len < 0 ? head : strpart(head, 0, len)
        el
            return ''
        en
    endf

    fun! fugitive#RevParse(rev, ...) abort
        let hash = s:ChompDefault('', [a:0 ? a:1 : s:Dir(), 'rev-parse', '--verify', a:rev, '--'])
        if hash =~# '^\x\{40,\}$'
            return hash
        en
        throw 'fugitive: failed to parse revision ' . a:rev
    endf

" Section: Git config

    fun! s:ConfigTimestamps(dir, dict) abort
        let files = ['/etc/gitconfig', '~/.gitconfig',
                    \ len($XDG_CONFIG_HOME) ? $XDG_CONFIG_HOME . '/git/config' : '~/.config/git/config']
        if len(a:dir)
            call add(files, fugitive#Find('.git/config', a:dir))
        en
        call extend(files, get(a:dict, 'include.path', []))
        return join(map(files, 'getftime(expand(v:val))'), ',')
    endf

    fun! s:ConfigCallback(r, into) abort
        let dict = a:into[1]
        if has_key(dict, 'job')
            call remove(dict, 'job')
        en
        let lines = a:r.exit_status ? [] : split(tr(join(a:r.stdout, "\1"), "\1\n", "\n\1"), "\1", 1)[0:-2]
        for line in lines
            let key = matchstr(line, "^[^\n]*")
            if !has_key(dict, key)
                let dict[key] = []
            en
            if len(key) ==# len(line)
                call add(dict[key], 1)
            el
                call add(dict[key], strpart(line, len(key) + 1))
            en
        endfor
        let callbacks = remove(dict, 'callbacks')
        lockvar! dict
        let a:into[0] = s:ConfigTimestamps(dict.git_dir, dict)
        for callback in callbacks
            call call(callback[0], [dict] + callback[1:-1])
        endfor
    endf

    let s:config_prototype = {}

    let s:config = {}
    fun! fugitive#ExpireConfig(...) abort
        if !a:0 || a:1 is# 0
            let s:config = {}
        el
            let key = a:1 is# '' ? '_' : s:GitDir(a:0 ? a:1 : -1)
            if len(key) && has_key(s:config, key)
                call remove(s:config, key)
            en
        en
    endf

    fun! fugitive#Config(...) abort
        let name = ''
        let default = get(a:, 3, '')
        if a:0 && type(a:1) == type(function('tr'))
            let dir = s:Dir()
            let callback = a:000
        elseif a:0 > 1 && type(a:2) == type(function('tr'))
            if type(a:1) == type({}) && has_key(a:1, 'GetAll')
                if has_key(a:1, 'callbacks')
                    call add(a:1.callbacks, a:000[1:-1])
                el
                    call call(a:2, [a:1] + a:000[2:-1])
                en
                return a:1
            el
                let dir = s:Dir(a:1)
                let callback = a:000[1:-1]
            en
        elseif a:0 >= 2 && type(a:2) == type({}) && has_key(a:2, 'GetAll')
            return get(fugitive#ConfigGetAll(a:1, a:2), 0, default)
        elseif a:0 >= 2
            let dir = s:Dir(a:2)
            let name = a:1
        elseif a:0 == 1 && type(a:1) == type({}) && has_key(a:1, 'GetAll')
            return a:1
        elseif a:0 == 1 && type(a:1) == type('') && a:1 =~# '^[[:alnum:]-]\+\.'
            let dir = s:Dir()
            let name = a:1
        elseif a:0 == 1
            let dir = s:Dir(a:1)
        el
            let dir = s:Dir()
        en
        let name = substitute(name, '^[^.]\+\|[^.]\+$', '\L&', 'g')
        let git_dir = s:GitDir(dir)
        let dir_key = len(git_dir) ? git_dir : '_'
        let [ts, dict] = get(s:config, dir_key, ['new', {}])
        if !has_key(dict, 'job') && ts !=# s:ConfigTimestamps(git_dir, dict)
            let dict = copy(s:config_prototype)
            let dict.git_dir = git_dir
            let into = ['running', dict]
            let dict.callbacks = []
            let exec = fugitive#Execute([dir, 'config', '--list', '-z', '--'], function('s:ConfigCallback'), into)
            if has_key(exec, 'job')
                let dict.job = exec.job
            en
            let s:config[dir_key] = into
        en
        if !exists('l:callback')
            call fugitive#Wait(dict)
        elseif has_key(dict, 'callbacks')
            call add(dict.callbacks, callback)
        el
            call call(callback[0], [dict] + callback[1:-1])
        en
        return len(name) ? get(fugitive#ConfigGetAll(name, dict), 0, default) : dict
    endf

    fun! fugitive#ConfigGetAll(name, ...) abort
        if a:0 && (type(a:name) !=# type('') || a:name !~# '^[[:alnum:]-]\+\.' && type(a:1) ==# type('') && a:1 =~# '^[[:alnum:]-]\+\.')
            let config = fugitive#Config(a:name)
            let name = a:1
        el
            let config = fugitive#Config(a:0 ? a:1 : s:Dir())
            let name = a:name
        en
        let name = substitute(name, '^[^.]\+\|[^.]\+$', '\L&', 'g')
        call fugitive#Wait(config)
        return name =~# '\.' ? copy(get(config, name, [])) : []
    endf

    fun! fugitive#ConfigGetRegexp(pattern, ...) abort
        if type(a:pattern) !=# type('')
            let config = fugitive#Config(a:name)
            let pattern = a:0 ? a:1 : '.*'
        el
            let config = fugitive#Config(a:0 ? a:1 : s:Dir())
            let pattern = a:pattern
        en
        call fugitive#Wait(config)
        let filtered = map(filter(copy(config), 'v:key =~# "\\." && v:key =~# pattern'), 'copy(v:val)')
        if pattern !~# '\\\@<!\%(\\\\\)*\\z[se]'
            return filtered
        en
        let transformed = {}
        for [k, v] in items(filtered)
            let k = matchstr(k, pattern)
            if len(k)
                let transformed[k] = v
            en
        endfor
        return transformed
    endf

    fun! s:config_GetAll(name) dict abort
        let name = substitute(a:name, '^[^.]\+\|[^.]\+$', '\L&', 'g')
        call fugitive#Wait(self)
        return name =~# '\.' ? copy(get(self, name, [])) : []
    endf

    fun! s:config_Get(name, ...) dict abort
        return get(self.GetAll(a:name), 0, a:0 ? a:1 : '')
    endf

    fun! s:config_GetRegexp(pattern) dict abort
        return fugitive#ConfigGetRegexp(self, a:pattern)
    endf

    call s:add_methods('config', ['GetAll', 'Get', 'GetRegexp'])

    fun! s:RemoteDefault(dir) abort
        let head = FugitiveHead(0, a:dir)
        let remote = len(head) ? FugitiveConfigGet('branch.' . head . '.remote', a:dir) : ''
        let i = 10
        while remote ==# '.' && i > 0
            let head = matchstr(FugitiveConfigGet('branch.' . head . '.merge', a:dir), 'refs/heads/\zs.*')
            let remote = len(head) ? FugitiveConfigGet('branch.' . head . '.remote', a:dir) : ''
            let i -= 1
        endwhile
        return remote =~# '^\.\=$' ? 'origin' : remote
    endf

    fun! s:SshParseHost(value) abort
        let patterns = []
        let negates = []
        for host in split(a:value, '\s\+')
            let pattern = substitute(host, '[\\^$.*~?]', '\=submatch(0) == "*" ? ".*" : submatch(0) == "?" ? "." : "\\" . submatch(0)', 'g')
            if pattern[0] ==# '!'
                call add(negates, '\&\%(^' . pattern[1 : -1] . '$\)\@!')
            el
                call add(patterns, pattern)
            en
        endfor
        return '^\%(' . join(patterns, '\|') . '\)$' . join(negates, '')
    endf

    fun! s:SshParseConfig(into, root, file, ...) abort
        if !filereadable(a:file)
            return a:into
        en
        let host = a:0 ? a:1 : '^\%(.*\)$'
        for line in readfile(a:file)
            let key = tolower(matchstr(line, '^\s*\zs\w\+\ze\s'))
            let value = matchstr(line, '^\s*\w\+\s\+\zs.*\S')
            if key ==# 'match'
                let host = value ==# 'all' ? '^\%(.*\)$' : ''
            elseif key ==# 'host'
                let host = s:SshParseHost(value)
            elseif key ==# 'include'
                call s:SshParseInclude(a:into, a:root, host, value)
            elseif len(key) && len(host)
                call extend(a:into, {key: []}, 'keep')
                call add(a:into[key], [host, value])
            en
        endfor
        return a:into
    endf

    fun! s:SshParseInclude(into, root, host, value) abort
        for glob in split(a:value)
            if glob !~# '^/'
                let glob = a:root . glob
            en
            for file in split(glob(glob), "\n")
                call s:SshParseConfig(a:into, a:root, file, a:host)
            endfor
        endfor
    endf

    unlet! s:ssh_config
    fun! fugitive#SshConfig(host, ...) abort
        if !exists('s:ssh_config')
            let s:ssh_config = {}
            for file in [expand("~/.ssh/config"), "/etc/ssh/ssh_config"]
                call s:SshParseConfig(s:ssh_config, substitute(file, '\w*$', '', ''), file)
            endfor
        en
        let host_config = {}
        for key in a:0 ? a:1 : keys(s:ssh_config)
            for [host_pattern, value] in get(s:ssh_config, key, [])
                if a:host =~# host_pattern
                    let host_config[key] = value
                    break
                en
            endfor
        endfor
        return host_config
    endf

    fun! fugitive#SshHostAlias(authority) abort
        let [_, user, host, port; __] = matchlist(a:authority, '^\%(\([^/@]\+\)@\)\=\(.\{-\}\)\%(:\(\d\+\)\)\=$')
        let c = fugitive#SshConfig(host, ['user', 'hostname', 'port'])
        if empty(user)
            let user = get(c, 'user', '')
        en
        if empty(port)
            let port = get(c, 'port', '')
        en
        return (len(user) ? user . '@' : '') . get(c, 'hostname', host) . (port =~# '^\%(22\)\=$' ? '' : ':' . port)
    endf

    fun! s:CurlResponse(result) abort
        let a:result.headers = {}
        for line in a:result.exit_status ? [] : remove(a:result, 'stdout')
            let header = matchlist(line, '^\([[:alnum:]-]\+\):\s\(.\{-\}\)'. "\r\\=$")
            if len(header)
                let k = tolower(header[1])
                if has_key(a:result.headers, k)
                    let a:result.headers[k] .= ', ' . header[2]
                el
                    let a:result.headers[k] = header[2]
                en
            elseif empty(line)
                break
            en
        endfor
    endf

    let s:remote_headers = {}

    fun! fugitive#RemoteHttpHeaders(remote) abort
        let remote = type(a:remote) ==# type({}) ? get(a:remote, 'remote', '') : a:remote
        if type(remote) !=# type('') || remote !~# '^https\=://.' || !s:executable('curl')
            return {}
        en
        let remote = substitute(remote, '#.*', '', '')
        if !has_key(s:remote_headers, remote)
            let url = remote . '/info/refs?service=git-upload-pack'
            let exec = s:JobExecute(
                        \ ['curl', '--disable', '--silent', '--max-time', '5', '-X', 'GET', '-I',
                        \ url], {}, [], [function('s:CurlResponse')], {})
            call fugitive#Wait(exec)
            let s:remote_headers[remote] = exec.headers
        en
        return s:remote_headers[remote]
    endf

    fun! s:UrlParse(url) abort
        let scp_authority = matchstr(a:url, '^[^:/]\+\ze:\%(//\)\@!')
        if len(scp_authority) && !(has('win32') && scp_authority =~# '^\a:[\/]')
            let url = {'scheme': 'ssh', 'authority': scp_authority, 'hash': '',
                        \ 'path': substitute(strpart(a:url, len(scp_authority) + 1), '[#?]', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')}
        elseif empty(a:url)
            let url = {'scheme': '', 'authority': '', 'path': '', 'hash': ''}
        el
            let match = matchlist(a:url, '^\([[:alnum:].+-]\+\)://\([^/]*\)\(/[^#]*\)\=\(#.*\)\=$')
            if empty(match)
                let url = {'scheme': 'file', 'authority': '', 'hash': '',
                            \ 'path': substitute(a:url, '[#?]', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')}
            el
                let url = {'scheme': match[1], 'authority': match[2], 'hash': match[4]}
                let url.path = empty(match[3]) ? '/' : match[3]
            en
        en
        return url
    endf

    fun! s:UrlPopulate(string, into) abort
        let url = a:into
        let url.protocol = substitute(url.scheme, '.\zs$', ':', '')
        let url.user = matchstr(url.authority, '.\{-\}\ze@', '', '')
        let url.host = substitute(url.authority, '.\{-\}@', '', '')
        let url.hostname = substitute(url.host, ':\d\+$', '', '')
        let url.port = matchstr(url.host, ':\zs\d\+$', '', '')
        let url.origin = substitute(url.scheme, '.\zs$', '://', '') . url.host
        let url.search = matchstr(url.path, '?.*')
        let url.pathname = '/' . matchstr(url.path, '^/\=\zs[^?]*')
        if (url.scheme ==# 'ssh' || url.scheme ==# 'git') && url.path[0:1] ==# '/~'
            let url.path = strpart(url.path, 1)
        en
        if url.path =~# '^/'
            let url.href = url.scheme . '://' . url.authority . url.path . url.hash
        elseif url.path =~# '^\~'
            let url.href = url.scheme . '://' . url.authority . '/' . url.path . url.hash
        elseif url.scheme ==# 'ssh' && url.authority !~# ':'
            let url.href = url.authority . ':' . url.path . url.hash
        el
            let url.href = a:string
        en
        let url.url = matchstr(url.href, '^[^#]*')
    endf

    fun! s:RemoteResolve(url, flags) abort
        let remote = s:UrlParse(a:url)
        if remote.scheme =~# '^https\=$' && index(a:flags, ':nohttp') < 0
            let headers = fugitive#RemoteHttpHeaders(a:url)
            let loc = matchstr(get(headers, 'location', ''), '^https\=://.\{-\}\ze/info/refs?')
            if len(loc)
                let remote = s:UrlParse(loc)
            el
                let remote.headers = headers
            en
        elseif remote.scheme ==# 'ssh'
            let remote.authority = fugitive#SshHostAlias(remote.authority)
        en
        return remote
    endf

    fun! s:ConfigLengthSort(i1, i2) abort
        return len(a:i2[0]) - len(a:i1[0])
    endf

    fun! s:RemoteCallback(config, into, flags, cb) abort
        if a:into.remote_name =~# '^\.\=$'
            let a:into.remote_name = s:RemoteDefault(a:config)
        en
        let url = a:into.remote_name

        if url ==# '.git'
            let url = s:GitDir(a:config)
        elseif url !~# ':\|^/\|^\a:[\/]\|^\.\.\=/'
            let url = FugitiveConfigGet('remote.' . url . '.url', a:config)
        en
        let instead_of = []
        for [k, vs] in items(fugitive#ConfigGetRegexp('^url\.\zs.\{-\}\ze\.insteadof$', a:config))
            for v in vs
                call add(instead_of, [v, k])
            endfor
        endfor
        call sort(instead_of, 's:ConfigLengthSort')
        for [orig, replacement] in instead_of
            if strpart(url, 0, len(orig)) ==# orig
                let url = replacement . strpart(url, len(orig))
                break
            en
        endfor
        if index(a:flags, ':noresolve') < 0
            call extend(a:into, s:RemoteResolve(url, a:flags))
        el
            call extend(a:into, s:UrlParse(url))
        en
        call s:UrlPopulate(url, a:into)
        if len(a:cb)
            call call(a:cb[0], [a:into] + a:cb[1:-1])
        en
    endf

    fun! s:Remote(dir, remote, flags, cb) abort
        let into = {'remote_name': a:remote, 'git_dir': s:GitDir(a:dir)}
        let config = fugitive#Config(a:dir, function('s:RemoteCallback'), into, a:flags, a:cb)
        if len(a:cb)
            return config
        el
            call fugitive#Wait(config)
            return into
        en
    endf

    fun! s:RemoteParseArgs(args) abort
        " Extract ':noresolve' style flags and an optional callback
        let args = []
        let flags = []
        let cb = copy(a:args)
        while len(cb)
            if type(cb[0]) ==# type(function('tr'))
                break
            elseif len(args) > 1 || type(cb[0]) ==# type('') && cb[0] =~# '^:'
                call add(flags, remove(cb, 0))
            el
                call add(args, remove(cb, 0))
            en
        endwhile

        " From the remaining 0-2 arguments, extract the remote and Git config
        let remote = ''
        if empty(args)
            let dir_or_config = s:Dir()
        elseif len(args) == 1 && type(args[0]) ==# type('') && args[0] !~# '^/\|^\a:[\\/]'
            let dir_or_config = s:Dir()
            let remote = args[0]
        elseif len(args) == 1
            let dir_or_config = args[0]
            if type(args[0]) ==# type({}) && has_key(args[0], 'remote_name')
                let remote = args[0].remote_name
            en
        elseif type(args[1]) !=# type('') || args[1] =~# '^/\|^\a:[\\/]'
            let dir_or_config = args[1]
            let remote = args[0]
        el
            let dir_or_config = args[0]
            let remote = args[1]
        en
        return [dir_or_config, remote, flags, cb]
    endf

    fun! fugitive#Remote(...) abort
        let [dir_or_config, remote, flags, cb] = s:RemoteParseArgs(a:000)
        return s:Remote(dir_or_config, remote, flags, cb)
    endf

    fun! s:RemoteUrlCallback(remote, callback) abort
        return call(a:callback[0], [a:remote.url] + a:callback[1:-1])
    endf

    fun! fugitive#RemoteUrl(...) abort
        let [dir_or_config, remote, flags, cb] = s:RemoteParseArgs(a:000)
        if len(cb)
            let cb = [function('s:RemoteUrlCallback'), cb]
        en
        let remote = s:Remote(dir_or_config, remote, flags, cb)
        return get(remote, 'url', remote)
    endf

" Section: Quickfix

    fun! s:QuickfixGet(nr, ...) abort
        if a:nr < 0
            return call('getqflist', a:000)
        el
            return call('getloclist', [a:nr] + a:000)
        en
    endf

    fun! s:QuickfixSet(nr, ...) abort
        if a:nr < 0
            return call('setqflist', a:000)
        el
            return call('setloclist', [a:nr] + a:000)
        en
    endf

    fun! s:QuickfixCreate(nr, opts) abort
        if has('patch-7.4.2200')
            call s:QuickfixSet(a:nr, [], ' ', a:opts)
        el
            call s:QuickfixSet(a:nr, [], ' ')
        en
    endf

    fun! s:QuickfixOpen(nr, mods) abort
        let mods = substitute(s:Mods(a:mods), '\<tab\>', '', '')
        return mods . (a:nr < 0 ? 'c' : 'l').'open' . (mods =~# '\<vertical\>' ? ' 20' : '')
    endf

    fun! s:QuickfixStream(nr, event, title, cmd, first, mods, callback, ...) abort
        call s:BlurStatus()
        let opts = {'title': a:title, 'context': {'items': []}}
        call s:QuickfixCreate(a:nr, opts)
        let event = (a:nr < 0 ? 'c' : 'l') . 'fugitive-' . a:event
        exe s:DoAutocmd('QuickFixCmdPre ' . event)
        let winnr = winnr()
        exe s:QuickfixOpen(a:nr, a:mods)
        if winnr != winnr()
            wincmd p
        en

        let buffer = []
        let lines = s:SystemList(a:cmd)[0]
        for line in lines
            call extend(buffer, call(a:callback, a:000 + [line]))
            if len(buffer) >= 20
                let contexts = map(copy(buffer), 'get(v:val, "context", {})')
                lockvar contexts
                call extend(opts.context.items, contexts)
                unlet contexts
                call s:QuickfixSet(a:nr, remove(buffer, 0, -1), 'a')
                if a:mods !~# '\<silent\>'
                    redraw
                en
            en
        endfor
        call extend(buffer, call(a:callback, a:000 + [0]))
        call extend(opts.context.items, map(copy(buffer), 'get(v:val, "context", {})'))
        lockvar opts.context.items
        call s:QuickfixSet(a:nr, buffer, 'a')

        exe s:DoAutocmd('QuickFixCmdPost ' . event)
        if a:first && len(s:QuickfixGet(a:nr))
            return (a:nr < 0 ? 'cfirst' : 'lfirst')
        el
            return 'exe'
        en
    endf

    fun! fugitive#Cwindow() abort
        if &buftype == 'quickfix'
            cwindow
        el
            botright cwindow
            if &buftype == 'quickfix'
                wincmd p
            en
        en
    endf

" Section: Repository Object

    let s:repo_prototype = {}
    let s:repos = {}

    fun! fugitive#repo(...) abort
        let dir = a:0 ? s:GitDir(a:1) : (len(s:GitDir()) ? s:GitDir() : FugitiveExtractGitDir(expand('%:p')))
        if dir !=# ''
            if has_key(s:repos, dir)
                let repo = get(s:repos, dir)
            el
                let repo = {'git_dir': dir}
                let s:repos[dir] = repo
            en
            return extend(repo, s:repo_prototype, 'keep')
        en
        call s:throw('not a Git repository')
    endf

    fun! s:repo_dir(...) dict abort
        return join([self.git_dir]+a:000,'/')
    endf

    fun! s:repo_tree(...) dict abort
        let dir = s:Tree(self.git_dir)
        if dir ==# ''
            call s:throw('no work tree')
        el
            return join([dir]+a:000,'/')
        en
    endf

    fun! s:repo_bare() dict abort
        if self.dir() =~# '/\.git$'
            return 0
        el
            return s:Tree(self.git_dir) ==# ''
        en
    endf

    fun! s:repo_find(object) dict abort
        return fugitive#Find(a:object, self.git_dir)
    endf

    fun! s:repo_translate(rev) dict abort
        return s:Slash(fugitive#Find(substitute(a:rev, '^/', ':(top)', ''), self.git_dir))
    endf

    fun! s:repo_head(...) dict abort
        return fugitive#Head(a:0 ? a:1 : 0, self.git_dir)
    endf

    call s:add_methods('repo',['dir','tree','bare','find','translate','head'])

    fun! s:repo_git_command(...) dict abort
        throw 'fugitive: fugitive#repo().git_command(...) has been replaced by FugitiveShellCommand(...)'
    endf

    fun! s:repo_git_chomp(...) dict abort
        return s:sub(system(fugitive#ShellCommand(a:000, self.git_dir)), '\n$', '')
    endf

    fun! s:repo_git_chomp_in_tree(...) dict abort
        return call(self.git_chomp, a:000, self)
    endf

    fun! s:repo_rev_parse(rev) dict abort
        return fugitive#RevParse(a:rev, self.git_dir)
    endf

    call s:add_methods('repo',['git_command','git_chomp','git_chomp_in_tree','rev_parse'])

    fun! s:repo_superglob(base) dict abort
        return map(fugitive#CompleteObject(a:base, self.git_dir), 'substitute(v:val, ''\\\(.\)'', ''\1'', "g")')
    endf

    call s:add_methods('repo',['superglob'])

    fun! s:repo_config(name) dict abort
        return FugitiveConfigGet(a:name, self.git_dir)
    endf

    fun! s:repo_user() dict abort
        let username = self.config('user.name')
        let useremail = self.config('user.email')
        return username.' <'.useremail.'>'
    endf

    call s:add_methods('repo',['config', 'user'])

" Section: File API

    fun! s:DirCommitFile(path) abort
        let vals = matchlist(s:Slash(a:path), '\c^fugitive:\%(//\)\=\(.\{-\}\)\%(//\|::\)\(\x\{40,\}\|[0-3]\)\(/.*\)\=$')
        if empty(vals)
            return ['', '', '']
        en
        return [s:Dir(vals[1])] + vals[2:3]
    endf

    fun! s:DirRev(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        return [dir, (commit =~# '^.$' ? ':' : '') . commit . substitute(file, '^/', ':', '')]
    endf

    let s:merge_heads = ['MERGE_HEAD', 'REBASE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD']
    fun! s:MergeHead(dir) abort
        let dir = fugitive#Find('.git/', a:dir)
        for head in s:merge_heads
            if filereadable(dir . head)
                return head
            en
        endfor
        return ''
    endf

    fun! s:Owner(path, ...) abort
        let dir = a:0 ? s:Dir(a:1) : s:Dir()
        if empty(dir)
            return ''
        en
        let actualdir = fugitive#Find('.git/', dir)
        let [pdir, commit, file] = s:DirCommitFile(a:path)
        if s:cpath(dir, pdir)
            if commit =~# '^\x\{40,\}$'
                return commit
            elseif commit ==# '2'
                return '@'
            elseif commit ==# '0'
                return ''
            en
            let merge_head = s:MergeHead(dir)
            if empty(merge_head)
                return ''
            en
            if commit ==# '3'
                return merge_head
            elseif commit ==# '1'
                return s:TreeChomp('merge-base', 'HEAD', merge_head, '--')
            en
        en
        let path = fnamemodify(a:path, ':p')
        if s:cpath(actualdir, strpart(path, 0, len(actualdir))) && a:path =~# 'HEAD$'
            return strpart(path, len(actualdir))
        en
        let refs = fugitive#Find('.git/refs', dir)
        if s:cpath(refs . '/', path[0 : len(refs)]) && path !~# '[\/]$'
            return strpart(path, len(refs) - 4)
        en
        return ''
    endf

    fun! fugitive#Real(url) abort
        if empty(a:url)
            return ''
        en
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if len(dir)
            let tree = s:Tree(dir)
            return FugitiveVimPath((len(tree) ? tree : dir) . file)
        en
        let pre = substitute(matchstr(a:url, '^\a\a\+\ze:'), '^.', '\u&', '')
        if len(pre) && pre !=? 'fugitive' && exists('*' . pre . 'Real')
            let url = {pre}Real(a:url)
        el
            let url = fnamemodify(a:url, ':p' . (a:url =~# '[\/]$' ? '' : ':s?[\/]$??'))
        en
        return FugitiveVimPath(empty(url) ? a:url : url)
    endf

    fun! fugitive#Path(url, ...) abort
        if empty(a:url)
            return ''
        en
        let dir = a:0 > 1 ? s:Dir(a:2) : s:Dir()
        let tree = s:Tree(dir)
        if !a:0
            return fugitive#Real(a:url)
        elseif a:1 =~# '\.$'
            let path = s:Slash(fugitive#Real(a:url))
            let cwd = getcwd()
            let lead = ''
            while s:cpath(tree . '/', (cwd . '/')[0 : len(tree)])
                if s:cpath(cwd . '/', path[0 : len(cwd)])
                    if strpart(path, len(cwd) + 1) =~# '^\.git\%(/\|$\)'
                        break
                    en
                    return a:1[0:-2] . (empty(lead) ? './' : lead) . strpart(path, len(cwd) + 1)
                en
                let cwd = fnamemodify(cwd, ':h')
                let lead .= '../'
            endwhile
            return a:1[0:-2] . path
        en
        let url = a:url
        let temp_state = s:TempState(url)
        if has_key(temp_state, 'origin_bufnr')
            let url = bufname(temp_state.origin_bufnr)
        en
        let url = s:Slash(fnamemodify(url, ':p'))
        if url =~# '/$' && s:Slash(a:url) !~# '/$'
            let url = url[0:-2]
        en
        let [argdir, commit, file] = s:DirCommitFile(a:url)
        if len(argdir) && s:cpath(argdir) !=# s:cpath(dir)
            let file = ''
        elseif len(dir) && s:cpath(url[0 : len(dir)]) ==# s:cpath(dir . '/')
            let file = '/.git'.url[strlen(dir) : -1]
        elseif len(tree) && s:cpath(url[0 : len(tree)]) ==# s:cpath(tree . '/')
            let file = url[len(tree) : -1]
        elseif s:cpath(url) ==# s:cpath(tree)
            let file = '/'
        en
        if empty(file) && a:1 =~# '^$\|^[.:]/$'
            return FugitiveGitPath(fugitive#Real(a:url))
        en
        return substitute(file, '^/', a:1, '')
    endf

    fun! s:Relative(...) abort
        return fugitive#Path(@%, a:0 ? a:1 : ':(top)', a:0 > 1 ? a:2 : s:Dir())
    endf

    fun! fugitive#Find(object, ...) abort
        if type(a:object) == type(0)
            let name = bufname(a:object)
            return FugitiveVimPath(name =~# '^$\|^/\|^\a\+:' ? name : getcwd() . '/' . name)
        elseif a:object =~# '^[~$]'
            let prefix = matchstr(a:object, '^[~$]\i*')
            let owner = expand(prefix)
            return FugitiveVimPath((len(owner) ? owner : prefix) . strpart(a:object, len(prefix)))
        en
        let rev = s:Slash(a:object)
        if rev =~# '^$\|^/\|^\%(\a\a\+:\).*\%(//\|::\)' . (has('win32') ? '\|^\a:/' : '')
            return FugitiveVimPath(a:object)
        elseif rev =~# '^\.\.\=\%(/\|$\)'
            return FugitiveVimPath(simplify(getcwd() . '/' . a:object))
        en
        let dir = call('s:GitDir', a:000)
        if empty(dir)
            let file = matchstr(a:object, '^\%(:\d:\|[^:]*:\)\zs\%(\.\.\=$\|\.\.\=/.*\|/.*\|\w:/.*\)')
            let dir = FugitiveExtractGitDir(file)
            if empty(dir)
                return ''
            en
        en
        let tree = s:Tree(dir)
        let urlprefix = s:DirUrlPrefix(dir)
        let base = len(tree) ? tree : urlprefix . '0'
        if rev ==# '.git'
            let f = len(tree) && len(getftype(tree . '/.git')) ? tree . '/.git' : dir
        elseif rev =~# '^\.git/'
            let f = strpart(rev, 5)
            let fdir = dir . '/'
            let cdir = FugitiveCommonDir(dir) . '/'
            if f =~# '^\.\./\.\.\%(/\|$\)'
                let f = simplify(len(tree) ? tree . f[2:-1] : fdir . f)
            elseif f =~# '^\.\.\%(/\|$\)'
                let f = base . f[2:-1]
            elseif cdir !=# fdir && (
                        \ f =~# '^\%(config\|hooks\|info\|logs/refs\|objects\|refs\|worktrees\)\%(/\|$\)' ||
                        \ f !~# '^\%(index$\|index\.lock$\|\w*MSG$\|\w*HEAD$\|logs/\w*HEAD$\|logs$\|rebase-\w\+\)\%(/\|$\)' &&
                        \ getftime(FugitiveVimPath(fdir . f)) < 0 && getftime(FugitiveVimPath(cdir . f)) >= 0)
                let f = simplify(cdir . f)
            el
                let f = simplify(fdir . f)
            en
        elseif rev ==# ':/'
            let f = tree
        elseif rev =~# '^\.\%(/\|$\)'
            let f = base . rev[1:-1]
        elseif rev =~# '^::\%(/\|\a\+\:\)'
            let f = rev[2:-1]
        elseif rev =~# '^::\.\.\=\%(/\|$\)'
            let f = simplify(getcwd() . '/' . rev[2:-1])
        elseif rev =~# '^::'
            let f = base . '/' . rev[2:-1]
        elseif rev =~# '^:\%([0-3]:\)\=\.\.\=\%(/\|$\)\|^:[0-3]:\%(/\|\a\+:\)'
            let f = rev =~# '^:\%([0-3]:\)\=\.' ? simplify(getcwd() . '/' . matchstr(rev, '\..*')) : rev[3:-1]
            if s:cpath(base . '/', (f . '/')[0 : len(base)])
                let f = urlprefix . +matchstr(rev, '^:\zs\d\ze:') . '/' . strpart(f, len(base) + 1)
            el
                let altdir = FugitiveExtractGitDir(f)
                if len(altdir) && !s:cpath(dir, altdir)
                    return fugitive#Find(a:object, altdir)
                en
            en
        elseif rev =~# '^:[0-3]:'
            let f = urlprefix . rev[1] . '/' . rev[3:-1]
        elseif rev ==# ':'
            let fdir = dir . '/'
            let f = fdir . 'index'
            if len($GIT_INDEX_FILE)
                let index_dir = substitute($GIT_INDEX_FILE, '[^/]\+$', '', '')
                if s:cpath(index_dir, fdir)
                    let f = FugitiveVimPath($GIT_INDEX_FILE)
                elseif s:cpath(resolve(FugitiveVimPath(index_dir)), fdir)
                    let f = resolve(FugitiveVimPath($GIT_INDEX_FILE))
                en
            en
        elseif rev =~# '^:(\%(top\|top,literal\|literal,top\|literal\))'
            let f = matchstr(rev, ')\zs.*')
            if f=~# '^\.\.\=\%(/\|$\)'
                let f = simplify(getcwd() . '/' . f)
            elseif f !~# '^/\|^\%(\a\a\+:\).*\%(//\|::\)' . (has('win32') ? '\|^\a:/' : '')
                let f = base . '/' . f
            en
        elseif rev =~# '^:/\@!'
            let f = urlprefix . '0/' . rev[1:-1]
        el
            if !exists('f')
                let commit = matchstr(rev, '^\%([^:.-]\|\.\.[^/:]\)[^:]*\|^:.*')
                let file = substitute(matchstr(rev, '^\%([^:.-]\|\.\.[^/:]\)[^:]*\zs:.*'), '^:', '/', '')
                if file =~# '^/\.\.\=\%(/\|$\)\|^//\|^/\a\+:'
                    let file = file =~# '^/\.' ? simplify(getcwd() . file) : file[1:-1]
                    if s:cpath(base . '/', (file . '/')[0 : len(base)])
                        let file = '/' . strpart(file, len(base) + 1)
                    el
                        let altdir = FugitiveExtractGitDir(file)
                        if len(altdir) && !s:cpath(dir, altdir)
                            return fugitive#Find(a:object, altdir)
                        en
                        return file
                    en
                en
                let commits = split(commit, '\.\.\.-\@!', 1)
                if len(commits) == 2
                    call map(commits, 'empty(v:val) ? "@" : v:val')
                    let commit = matchstr(s:ChompDefault('', [dir, 'merge-base'] + commits + ['--']), '\<[0-9a-f]\{40,\}\>')
                en
                if commit !~# '^[0-9a-f]\{40,\}$\|^$'
                    let commit = matchstr(s:ChompDefault('', [dir, 'rev-parse', '--verify', commit . (len(file) ? '^{}' : ''), '--']), '\<[0-9a-f]\{40,\}\>')
                    if empty(commit) && len(file)
                        let commit = repeat('0', 40)
                    en
                en
                if len(commit)
                    let f = urlprefix . commit . file
                el
                    let f = base . '/' . substitute(rev, '^:/:\=\|^[^:]\+:', '', '')
                en
            en
        en
        return FugitiveVimPath(f)
    endf

    fun! s:Generate(object, ...) abort
        let dir = a:0 ? a:1 : s:Dir()
        let f = fugitive#Find(a:object, dir)
        if !empty(f)
            return f
        elseif a:object ==# ':/'
            return len(dir) ? FugitiveVimPath(s:DirUrlPrefix(dir) . '0') : '.'
        en
        let file = matchstr(a:object, '^\%(:\d:\|[^:]*:\)\zs.*')
        return fnamemodify(FugitiveVimPath(len(file) ? file : a:object), ':p')
    endf

    fun! s:DotRelative(path, ...) abort
        let cwd = a:0 ? a:1 : getcwd()
        let path = substitute(a:path, '^[~$]\i*', '\=expand(submatch(0))', '')
        if len(cwd) && s:cpath(cwd . '/', (path . '/')[0 : len(cwd)])
            return '.' . strpart(path, len(cwd))
        en
        return a:path
    endf

    fun! fugitive#Object(...) abort
        let dir = a:0 > 1 ? s:Dir(a:2) : s:Dir()
        let [fdir, rev] = s:DirRev(a:0 ? a:1 : @%)
        if s:cpath(dir) !=# s:cpath(fdir)
            let rev = ''
        en
        let tree = s:Tree(dir)
        let full = a:0 ? a:1 : s:BufName('%')
        let full = fnamemodify(full, ':p' . (s:Slash(full) =~# '/$' ? '' : ':s?/$??'))
        if empty(rev) && empty(tree)
            return FugitiveGitPath(full)
        elseif empty(rev)
            let rev = fugitive#Path(full, './', dir)
            if rev =~# '^\./.git\%(/\|$\)'
                return FugitiveGitPath(full)
            en
        en
        if rev !~# '^\.\%(/\|$\)' || s:cpath(getcwd(), tree)
            return rev
        el
            return FugitiveGitPath(tree . rev[1:-1])
        en
    endf

    let s:var = '\%(<\%(cword\|cWORD\|cexpr\|cfile\|sfile\|slnum\|afile\|abuf\|amatch' . (has('clientserver') ? '\|client' : '') . '\)>\|%\|#<\=\d\+\|##\=\)'
    let s:flag = '\%(:[p8~.htre]\|:g\=s\(.\).\{-\}\1.\{-\}\1\)'
    let s:expand = '\%(\(' . s:var . '\)\(' . s:flag . '*\)\(:S\)\=\)'

    fun! s:BufName(var) abort
        if a:var ==# '%'
            return bufname(get(s:TempState(), 'origin_bufnr', ''))
        elseif a:var =~# '^#\d*$'
            let nr = get(s:TempState(+a:var[1:-1]), 'origin_bufnr', '')
            return bufname(nr ? nr : +a:var[1:-1])
        el
            return expand(a:var)
        en
    endf

    fun! s:ExpandVarLegacy(str) abort
        if get(g:, 'fugitive_legacy_quoting', 0)
            return substitute(a:str, '\\\ze[%#!]', '', 'g')
        el
            return a:str
        en
    endf

    fun! s:ExpandVar(other, var, flags, esc, ...) abort
        let cwd = a:0 ? a:1 : getcwd()
        if a:other =~# '^\'
            return a:other[1:-1]
        elseif a:other =~# '^'''
            return s:ExpandVarLegacy(substitute(a:other[1:-2], "''", "'", "g"))
        elseif a:other =~# '^"'
            return s:ExpandVarLegacy(substitute(a:other[1:-2], '""', '"', "g"))
        elseif a:other =~# '^!'
            let buffer = s:BufName(len(a:other) > 1 ? '#'. a:other[1:-1] : '%')
            let owner = s:Owner(buffer)
            return len(owner) ? owner : '@'
        elseif a:other =~# '^\~[~.]$'
            return s:Slash(getcwd())
        elseif len(a:other)
            return expand(a:other)
        elseif a:var ==# '<cfile>'
            let bufnames = [expand('<cfile>')]
            if v:version >= 704 && get(maparg('<Plug><cfile>', 'c', 0, 1), 'expr')
                try
                    let bufnames = [eval(maparg('<Plug><cfile>', 'c'))]
                    if bufnames[0] ==# "\<C-R>\<C-F>"
                        let bufnames = [expand('<cfile>')]
                    en
                catch
                endtry
            en
        elseif a:var =~# '^<'
            let bufnames = [s:BufName(a:var)]
        elseif a:var ==# '##'
            let bufnames = map(argv(), 'fugitive#Real(v:val)')
        el
            let bufnames = [fugitive#Real(s:BufName(a:var))]
        en
        let files = []
        for bufname in bufnames
            let flags = a:flags
            let file = s:DotRelative(bufname, cwd)
            while len(flags)
                let flag = matchstr(flags, s:flag)
                let flags = strpart(flags, len(flag))
                if flag ==# ':.'
                    let file = s:DotRelative(fugitive#Real(file), cwd)
                el
                    let file = fnamemodify(file, flag)
                en
            endwhile
            let file = s:Slash(file)
            if file =~# '^fugitive://'
                let [dir, commit, file_candidate] = s:DirCommitFile(file)
                let tree = s:Tree(dir)
                if len(tree) && len(file_candidate)
                    let file = (commit =~# '^.$' ? ':' : '') . commit . ':' .
                                \ s:DotRelative(tree . file_candidate)
                elseif empty(file_candidate) && commit !~# '^.$'
                    let file = commit
                en
            en
            call add(files, len(a:esc) ? shellescape(file) : file)
        endfor
        return join(files, "\1")
    endf

    fun! s:Expand(rev, ...) abort
        if a:rev =~# '^>\=:[0-3]$'
            let file = len(expand('%')) ? a:rev[-2:-1] . ':%' : '%'
        elseif a:rev =~# '^>\%(:\=/\)\=$'
            let file = '%'
        elseif a:rev ==# '>:'
            let file = empty(s:DirCommitFile(@%)[0]) ? ':0:%' : '%'
        elseif a:rev =~# '^>[> ]\@!'
            let rev = (a:rev =~# '^>[~^]' ? '!' : '') . a:rev[1:-1]
            let prefix = matchstr(rev, '^\%(\\.\|{[^{}]*}\|[^:]\)*')
            if prefix !=# rev
                let file = rev
            el
                let file = len(expand('%')) ? rev . ':%' : '%'
            en
        el
            let file = a:rev
        en
        return substitute(file,
                    \ '\(\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\|^\~[~.]\)\|' . s:expand,
                    \ '\=tr(s:ExpandVar(submatch(1),submatch(2),submatch(3),"", a:0 ? a:1 : getcwd()), "\1", " ")', 'g')
    endf

    fun! fugitive#Expand(object) abort
        return substitute(a:object,
                    \ '\(\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\|^\~[~.]\)\|' . s:expand,
                    \ '\=tr(s:ExpandVar(submatch(1),submatch(2),submatch(3),submatch(5)), "\1", " ")', 'g')
    endf

    fun! s:SplitExpandChain(string, ...) abort
        let list = []
        let string = a:string
        let dquote = '"\%([^"]\|""\|\\"\)*"\|'
        let cwd = a:0 ? a:1 : getcwd()
        while string =~# '\S'
            if string =~# '^\s*|'
                return [list, substitute(string, '^\s*', '', '')]
            en
            let arg = matchstr(string, '^\s*\%(' . dquote . '''[^'']*''\|\\.\|[^[:space:] |]\)\+')
            let string = strpart(string, len(arg))
            let arg = substitute(arg, '^\s\+', '', '')
            if !exists('seen_separator')
                let arg = substitute(arg, '^\%([^:.][^:]*:\|^:\%((literal)\)\=\|^:[0-3]:\)\=\zs\.\.\=\%(/.*\)\=$',
                            \ '\=s:DotRelative(s:Slash(simplify(getcwd() . "/" . submatch(0))), cwd)', '')
            en
            let arg = substitute(arg,
                        \ '\(' . dquote . '''\%(''''\|[^'']\)*''\|\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\|^\~[~]\|^\~\w*\|\$\w\+\)\|' . s:expand,
                        \ '\=s:ExpandVar(submatch(1),submatch(2),submatch(3),submatch(5), cwd)', 'g')
            call extend(list, split(arg, "\1", 1))
            if arg ==# '--'
                let seen_separator = 1
            en
        endwhile
        return [list, '']
    endf

    let s:trees = {}
    let s:indexes = {}
    fun! s:TreeInfo(dir, commit) abort
        if a:commit =~# '^:\=[0-3]$'
            let index = get(s:indexes, a:dir, [])
            let newftime = getftime(fugitive#Find('.git/index', a:dir))
            if get(index, 0, -1) < newftime
                let [lines, exec_error] = s:LinesError([a:dir, 'ls-files', '--stage', '--'])
                let s:indexes[a:dir] = [newftime, {'0': {}, '1': {}, '2': {}, '3': {}}]
                if exec_error
                    return [{}, -1]
                en
                for line in lines
                    let [info, filename] = split(line, "\t")
                    let [mode, sha, stage] = split(info, '\s\+')
                    let s:indexes[a:dir][1][stage][filename] = [newftime, mode, 'blob', sha, -2]
                    while filename =~# '/'
                        let filename = substitute(filename, '/[^/]*$', '', '')
                        let s:indexes[a:dir][1][stage][filename] = [newftime, '040000', 'tree', '', 0]
                    endwhile
                endfor
            en
            return [get(s:indexes[a:dir][1], a:commit[-1:-1], {}), newftime]
        elseif a:commit =~# '^\x\{40,\}$'
            if !has_key(s:trees, a:dir)
                let s:trees[a:dir] = {}
            en
            if !has_key(s:trees[a:dir], a:commit)
                let ftime = s:ChompDefault('', [a:dir, 'log', '-1', '--pretty=format:%ct', a:commit, '--'])
                if empty(ftime)
                    let s:trees[a:dir][a:commit] = [{}, -1]
                    return s:trees[a:dir][a:commit]
                en
                let s:trees[a:dir][a:commit] = [{}, +ftime]
                let [lines, exec_error] = s:LinesError([a:dir, 'ls-tree', '-rtl', '--full-name', a:commit, '--'])
                if exec_error
                    return s:trees[a:dir][a:commit]
                en
                for line in lines
                    let [info, filename] = split(line, "\t")
                    let [mode, type, sha, size] = split(info, '\s\+')
                    let s:trees[a:dir][a:commit][0][filename] = [+ftime, mode, type, sha, +size, filename]
                endfor
            en
            return s:trees[a:dir][a:commit]
        en
        return [{}, -1]
    endf

    fun! s:PathInfo(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if empty(dir) || !get(g:, 'fugitive_file_api', 1)
            return [-1, '000000', '', '', -1]
        en
        let path = substitute(file[1:-1], '/*$', '', '')
        let [tree, ftime] = s:TreeInfo(dir, commit)
        let entry = empty(path) ? [ftime, '040000', 'tree', '', -1] : get(tree, path, [])
        if empty(entry) || file =~# '/$' && entry[2] !=# 'tree'
            return [-1, '000000', '', '', -1]
        el
            return entry
        en
    endf

    fun! fugitive#simplify(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if empty(dir)
            return ''
        en
        if file =~# '/\.\.\%(/\|$\)'
            let tree = s:Tree(dir)
            if len(tree)
                let path = simplify(tree . file)
                if strpart(path . '/', 0, len(tree) + 1) !=# tree . '/'
                    return FugitiveVimPath(path)
                en
            en
        en
        return FugitiveVimPath('fugitive://' . simplify(dir) . '//' . commit . simplify(file))
    endf

    fun! fugitive#resolve(url) abort
        let url = fugitive#simplify(a:url)
        if url =~? '^fugitive:'
            return url
        el
            return resolve(url)
        en
    endf

    fun! fugitive#getftime(url) abort
        return s:PathInfo(a:url)[0]
    endf

    fun! fugitive#getfsize(url) abort
        let entry = s:PathInfo(a:url)
        if entry[4] == -2 && entry[2] ==# 'blob' && len(entry[3])
            let dir = s:DirCommitFile(a:url)[0]
            let entry[4] = +s:ChompDefault(-1, [dir, 'cat-file', '-s', entry[3]])
        en
        return entry[4]
    endf

    fun! fugitive#getftype(url) abort
        return get({'tree': 'dir', 'blob': 'file'}, s:PathInfo(a:url)[2], '')
    endf

    fun! fugitive#filereadable(url) abort
        return s:PathInfo(a:url)[2] ==# 'blob'
    endf

    fun! fugitive#filewritable(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if commit !~# '^\d$' || !filewritable(fugitive#Find('.git/index', dir))
            return 0
        en
        return s:PathInfo(a:url)[2] ==# 'blob' ? 1 : 2
    endf

    fun! fugitive#isdirectory(url) abort
        return s:PathInfo(a:url)[2] ==# 'tree'
    endf

    fun! fugitive#getfperm(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        let perm = getfperm(dir)
        let fperm = s:PathInfo(a:url)[1]
        if fperm ==# '040000'
            let fperm = '000755'
        en
        if fperm !~# '[15]'
            let perm = tr(perm, 'x', '-')
        en
        if fperm !~# '[45]$'
            let perm = tr(perm, 'rw', '--')
        en
        if commit !~# '^\d$'
            let perm = tr(perm, 'w', '-')
        en
        return perm ==# '---------' ? '' : perm
    endf

    fun! s:UpdateIndex(dir, info) abort
        let info = join(a:info[0:-2]) . "\t" . a:info[-1] . "\n"
        let [error, exec_error] = s:StdoutToFile('', [a:dir, 'update-index', '--index-info'], info)
        return !exec_error ? '' : len(error) ? error : 'unknown update-index error'
    endf

    fun! fugitive#setfperm(url, perm) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        let entry = s:PathInfo(a:url)
        let perm = fugitive#getfperm(a:url)
        if commit !~# '^\d$' || entry[2] !=# 'blob' ||
                \ substitute(perm, 'x', '-', 'g') !=# substitute(a:perm, 'x', '-', 'g')
            return -2
        en
        let error = s:UpdateIndex(dir, [a:perm =~# 'x' ? '000755' : '000644', entry[3], commit, file[1:-1]])
        return len(error) ? -1 : 0
    endf

    if !exists('s:blobdirs')
        let s:blobdirs = {}
    en
    fun! s:BlobTemp(url) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if empty(file)
            return ''
        en
        if !has_key(s:blobdirs, dir)
            let s:blobdirs[dir] = tempname()
        en
        let tempfile = s:blobdirs[dir] . '/' . commit . file
        let tempparent = fnamemodify(tempfile, ':h')
        if !isdirectory(tempparent)
            call mkdir(tempparent, 'p')
        elseif isdirectory(tempfile)
            if commit =~# '^\d$' && has('patch-7.4.1107')
                call delete(tempfile, 'rf')
            el
                return ''
            en
        en
        if commit =~# '^\d$' || !filereadable(tempfile)
            let rev = s:DirRev(a:url)[1]
            let blob_or_filters = fugitive#GitVersion(2, 11) ? '--filters' : 'blob'
            let exec_error = s:StdoutToFile(tempfile, [dir, 'cat-file', blob_or_filters, rev])[1]
            if exec_error
                call delete(tempfile)
                return ''
            en
        en
        return s:Resolve(tempfile)
    endf

    fun! fugitive#readfile(url, ...) abort
        let entry = s:PathInfo(a:url)
        if entry[2] !=# 'blob'
            return []
        en
        let temp = s:BlobTemp(a:url)
        if empty(temp)
            return []
        en
        return call('readfile', [temp] + a:000)
    endf

    fun! fugitive#writefile(lines, url, ...) abort
        let url = type(a:url) ==# type('') ? a:url : ''
        let [dir, commit, file] = s:DirCommitFile(url)
        let entry = s:PathInfo(url)
        if commit =~# '^\d$' && entry[2] !=# 'tree'
            let temp = tempname()
            if a:0 && a:1 =~# 'a' && entry[2] ==# 'blob'
                call writefile(fugitive#readfile(url, 'b'), temp, 'b')
            en
            call call('writefile', [a:lines, temp] + a:000)
            let hash = s:ChompDefault('', [dir, '--literal-pathspecs', 'hash-object', '-w', FugitiveGitPath(temp)])
            let mode = entry[1] !=# '000000' ? entry[1] : '100644'
            if hash =~# '^\x\{40,\}$'
                let error = s:UpdateIndex(dir, [mode, hash, commit, file[1:-1]])
                if empty(error)
                    return 0
                en
            en
        en
        return call('writefile', [a:lines, a:url] + a:000)
    endf

    let s:globsubs = {
                \ '/**/': '/\%([^./][^/]*/\)*',
                \ '/**': '/\%([^./][^/]\+/\)*[^./][^/]*',
                \ '**/': '[^/]*\%(/[^./][^/]*\)*',
                \ '**': '.*',
                \ '/*': '/[^/.][^/]*',
                \ '*': '[^/]*',
                \ '?': '[^/]'}
    fun! fugitive#glob(url, ...) abort
        let [dirglob, commit, glob] = s:DirCommitFile(a:url)
        let append = matchstr(glob, '/*$')
        let glob = substitute(glob, '/*$', '', '')
        let pattern = '^' . substitute(glob, '/\=\*\*/\=\|/\=\*\|[.?\$]\|^^', '\=get(s:globsubs, submatch(0), "\\" . submatch(0))', 'g')[1:-1] . '$'
        let results = []
        for dir in dirglob =~# '[*?]' ? split(glob(dirglob), "\n") : [dirglob]
            if empty(dir) || !get(g:, 'fugitive_file_api', 1) || !filereadable(fugitive#Find('.git/HEAD', dir))
                continue
            en
            let files = items(s:TreeInfo(dir, commit)[0])
            if len(append)
                call filter(files, 'v:val[1][2] ==# "tree"')
            en
            call map(files, 'v:val[0]')
            call filter(files, 'v:val =~# pattern')
            let prepend = s:DirUrlPrefix(dir) . substitute(commit, '^:', '', '') . '/'
            call sort(files)
            call map(files, 'FugitiveVimPath(prepend . v:val . append)')
            call extend(results, files)
        endfor
        if a:0 > 1 && a:2
            return results
        el
            return join(results, "\n")
        en
    endf

    fun! fugitive#delete(url, ...) abort
        let [dir, commit, file] = s:DirCommitFile(a:url)
        if a:0 && len(a:1) || commit !~# '^\d$'
            return -1
        en
        let entry = s:PathInfo(a:url)
        if entry[2] !=# 'blob'
            return -1
        en
        let error = s:UpdateIndex(dir, ['000000', '0000000000000000000000000000000000000000', commit, file[1:-1]])
        return len(error) ? -1 : 0
    endf

" Section: Buffer Object

    let s:buffer_prototype = {}

    fun! fugitive#buffer(...) abort
        let buffer = {'#': bufnr(a:0 ? a:1 : '%')}
        call extend(buffer, s:buffer_prototype, 'keep')
        return buffer
    endf

    fun! s:buffer_repo() dict abort
        return fugitive#repo(self['#'])
    endf

    fun! s:buffer_type(...) dict abort
        return 'see per type events at :help fugitive-autocommands'
    endf

    call s:add_methods('buffer', ['repo', 'type'])

" Section: Completion

    fun! s:FilterEscape(items, ...) abort
        let items = copy(a:items)
        call map(items, 'fnameescape(v:val)')
        if !a:0 || type(a:1) != type('')
            let match = ''
        el
            let match = substitute(a:1, '^[+>]\|\\\@<![' . substitute(s:fnameescape, '\\', '', '') . ']', '\\&', 'g')
        en
        let cmp = s:FileIgnoreCase(1) ? '==?' : '==#'
        return filter(items, 'strpart(v:val, 0, strlen(match)) ' . cmp . ' match')
    endf

    fun! s:GlobComplete(lead, pattern, ...) abort
        if a:lead ==# '/'
            return []
        elseif v:version >= 704
            let results = glob(a:lead . a:pattern, a:0 ? a:1 : 0, 1)
        el
            let results = split(glob(a:lead . a:pattern), "\n")
        en
        call map(results, 'v:val !~# "/$" && isdirectory(v:val) ? v:val."/" : v:val')
        call map(results, 'v:val[ strlen(a:lead) : -1 ]')
        return results
    endf

    fun! fugitive#CompletePath(base, ...) abort
        let dir = a:0 == 1 ? a:1 : a:0 >= 3 ? a:3 : s:Dir()
        let stripped = matchstr(a:base, '^\%(:/:\=\|:(top)\|:(top,literal)\|:(literal,top)\)')
        let base = strpart(a:base, len(stripped))
        if len(stripped) || a:0 < 4
            let root = s:Tree(dir)
        el
            let root = a:4
        en
        if root !=# '/' && len(root)
            let root .= '/'
        en
        if empty(stripped)
            let stripped = matchstr(a:base, '^\%(:(literal)\|:\)')
            let base = strpart(a:base, len(stripped))
        en
        if base =~# '^\.git/' && len(dir)
            let pattern = s:gsub(base[5:-1], '/', '*&').'*'
            let fdir = fugitive#Find('.git/', dir)
            let matches = s:GlobComplete(fdir, pattern)
            let cdir = fugitive#Find('.git/refs', dir)[0 : -5]
            if len(cdir) && s:cpath(fdir) !=# s:cpath(cdir)
                call extend(matches, s:GlobComplete(cdir, pattern))
            en
            call s:Uniq(matches)
            call map(matches, "'.git/' . v:val")
        elseif base =~# '^\~/'
            let matches = map(s:GlobComplete(expand('~/'), base[2:-1] . '*'), '"~/" . v:val')
        elseif a:base =~# '^/\|^\a\+:\|^\.\.\=/'
            let matches = s:GlobComplete('', base . '*')
        elseif len(root)
            let matches = s:GlobComplete(root, s:gsub(base, '/', '*&').'*')
        el
            let matches = []
        en
        call map(matches, 's:fnameescape(s:Slash(stripped . v:val))')
        return matches
    endf

    fun! fugitive#PathComplete(...) abort
        return call('fugitive#CompletePath', a:000)
    endf

    fun! s:CompleteHeads(dir) abort
        if empty(a:dir)
            return []
        en
        let dir = fugitive#Find('.git/', a:dir)
        return sort(filter(['HEAD', 'FETCH_HEAD', 'ORIG_HEAD'] + s:merge_heads, 'filereadable(dir . v:val)')) +
                    \ sort(s:LinesError([a:dir, 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes'])[0])
    endf

    fun! fugitive#CompleteObject(base, ...) abort
        let dir = a:0 == 1 ? a:1 : a:0 >= 3 ? a:3 : s:Dir()
        let tree = s:Tree(dir)
        let cwd = getcwd()
        let subdir = ''
        if len(tree) && s:cpath(tree . '/', cwd[0 : len(tree)])
            let subdir = strpart(cwd, len(tree) + 1) . '/'
        en
        let base = s:Expand(a:base)

        if a:base =~# '^!\d*$' && base !~# '^!'
            return [base]
        elseif base =~# '^\.\=/\|^:(' || base !~# ':'
            let results = []
            if base =~# '^refs/'
                let cdir = fugitive#Find('.git/refs', dir)[0 : -5]
                let results += map(s:GlobComplete(cdir, base . '*'), 's:Slash(v:val)')
                call map(results, 's:fnameescape(v:val)')
            elseif base !~# '^\.\=/\|^:('
                let heads = s:CompleteHeads(dir)
                if filereadable(fugitive#Find('.git/refs/stash', dir))
                    let heads += ["stash"]
                    let heads += sort(s:LinesError(["stash","list","--pretty=format:%gd"], dir)[0])
                en
                let results += s:FilterEscape(heads, fnameescape(base))
            en
            let results += a:0 == 1 || a:0 >= 3 ? fugitive#CompletePath(base, 0, '', dir, a:0 >= 4 ? a:4 : tree) : fugitive#CompletePath(base)
            return results

        elseif base =~# '^:'
            let entries = s:LinesError(['ls-files','--stage'], dir)[0]
            if base =~# ':\./'
                call map(entries, 'substitute(v:val, "\\M\t\\zs" . subdir, "./", "")')
            en
            call map(entries,'s:sub(v:val,".*(\\d)\\t(.*)",":\\1:\\2")')
            if base !~# '^:[0-3]\%(:\|$\)'
                call filter(entries,'v:val[1] == "0"')
                call map(entries,'v:val[2:-1]')
            en

        el
            let parent = matchstr(base, '.*[:/]')
            let entries = s:LinesError(['ls-tree', substitute(parent,  ':\zs\./', '\=subdir', '')], dir)[0]
            call map(entries,'s:sub(v:val,"^04.*\\zs$","/")')
            call map(entries,'parent.s:sub(v:val,".*\t","")')
        en
        return s:FilterEscape(entries, fnameescape(base))
    endf

    fun! s:CompleteSub(subcommand, A, L, P, ...) abort
        let pre = strpart(a:L, 0, a:P)
        if pre =~# ' -- '
            return fugitive#CompletePath(a:A)
        elseif a:A =~# '^-' || a:A is# 0
            return s:FilterEscape(split(s:ChompDefault('', [a:subcommand, '--git-completion-helper']), ' '), a:A)
        elseif !a:0
            return fugitive#CompleteObject(a:A, s:Dir())
        elseif type(a:1) == type(function('tr'))
            return call(a:1, [a:A, a:L, a:P] + (a:0 > 1 ? a:2 : []))
        el
            return s:FilterEscape(a:1, a:A)
        en
    endf

    fun! s:CompleteRevision(A, L, P, ...) abort
        return s:FilterEscape(s:CompleteHeads(a:0 ? a:1 : s:Dir()), a:A)
    endf

    fun! s:CompleteRemote(A, L, P, ...) abort
        let dir = a:0 ? a:1 : s:Dir()
        let remote = matchstr(a:L, '\u\w*[! ] *.\{-\}\s\@<=\zs[^-[:space:]]\S*\ze ')
        if !empty(remote)
            let matches = s:LinesError([dir, 'ls-remote', remote])[0]
            call filter(matches, 'v:val =~# "\t" && v:val !~# "{"')
            call map(matches, 's:sub(v:val, "^.*\t%(refs/%(heads/|tags/)=)=", "")')
        el
            let matches = s:LinesError([dir, 'remote'])[0]
        en
        return s:FilterEscape(matches, a:A)
    endf

" Section: Buffer auto-commands

    aug  fugitive_dummy_events
        au!
        au User Fugitive* "
        au BufWritePre,FileWritePre,FileWritePost * "
        au BufNewFile * "
        au QuickfixCmdPre,QuickfixCmdPost * "
    aug  END

    fun! s:ReplaceCmd(cmd) abort
        let temp = tempname()
        let [err, exec_error] = s:StdoutToFile(temp, a:cmd)
        if exec_error
            throw 'fugitive: ' . (len(err) ? substitute(err, "\n$", '', '') : 'unknown error running ' . string(a:cmd))
        en
        setl  noswapfile
        silent exe 'lockmarks keepalt noautocmd 0read ++edit' s:fnameescape(temp)
        if &foldenable && foldlevel('$') > 0
            set nofoldenable
            silent keepjumps $delete _
            set foldenable
        el
            silent keepjumps $delete _
        en
        call delete(temp)
        if s:cpath(s:AbsoluteVimPath(bufnr('$')), temp)
            silent! noautocmd execute bufnr('$') . 'bwipeout'
        en
    endf

    fun! s:QueryLog(refspec, limit) abort
        let lines = s:LinesError(['log', '-n', '' . a:limit, '--pretty=format:%h%x09%s'] + a:refspec + ['--'])[0]
        call map(lines, 'split(v:val, "\t", 1)')
        call map(lines, '{"type": "Log", "commit": v:val[0], "subject": join(v:val[1 : -1], "\t")}')
        return lines
    endf

    fun! s:FormatLog(dict) abort
        return a:dict.commit . ' ' . a:dict.subject
    endf

    fun! s:FormatRebase(dict) abort
        return a:dict.status . ' ' . a:dict.commit . ' ' . a:dict.subject
    endf

    fun! s:FormatFile(dict) abort
        return a:dict.status . ' ' . a:dict.filename
    endf

    fun! s:Format(val) abort
        if type(a:val) == type({})
            return s:Format{a:val.type}(a:val)
        elseif type(a:val) == type([])
            return map(copy(a:val), 's:Format(v:val)')
        el
            return '' . a:val
        en
    endf

    fun! s:AddHeader(key, value) abort
        if empty(a:value)
            return
        en
        let before = 1
        while !empty(getline(before))
            let before += 1
        endwhile
        call append(before - 1, [a:key . ':' . (len(a:value) ? ' ' . a:value : '')])
        if before == 1 && line('$') == 2
            silent keepjumps 2delete _
        en
    endf

    fun! s:AddSection(label, lines, ...) abort
        let note = a:0 ? a:1 : ''
        if empty(a:lines) && empty(note)
            return
        en
        call append(line('$'), ['', a:label . (len(note) ? ': ' . note : ' (' . len(a:lines) . ')')] + s:Format(a:lines))
    endf

    fun! s:AddLogSection(label, refspec) abort
        let limit = 256
        let log = s:QueryLog(a:refspec, limit)
        if empty(log)
            return
        elseif len(log) == limit
            call remove(log, -1)
            let label = a:label . ' (' . (limit - 1). '+)'
        el
            let label = a:label . ' (' . len(log) . ')'
        en
        call append(line('$'), ['', label] + s:Format(log))
    endf

    let s:rebase_abbrevs = {
                \ 'p': 'pick',
                \ 'r': 'reword',
                \ 'e': 'edit',
                \ 's': 'squash',
                \ 'f': 'fixup',
                \ 'x': 'exec',
                \ 'd': 'drop',
                \ 'l': 'label',
                \ 't': 'reset',
                \ 'm': 'merge',
                \ 'b': 'break',
                \ }

    fun! fugitive#BufReadStatus(...) abort
        let amatch = s:Slash(expand('%:p'))
        unlet! b:fugitive_reltime b:fugitive_type
        try
            doautocmd BufReadPre
            let config = fugitive#Config()

            let cmd = [fnamemodify(amatch, ':h')]
            setl  noreadonly modifiable nomodeline buftype=nowrite
            if s:cpath(fnamemodify($GIT_INDEX_FILE !=# '' ? FugitiveVimPath($GIT_INDEX_FILE) : fugitive#Find('.git/index'), ':p')) !=# s:cpath(amatch)
                let cmd += [{'env': {'GIT_INDEX_FILE': FugitiveGitPath(amatch)}}]
            en

            if fugitive#GitVersion(2, 15)
                call add(cmd, '--no-optional-locks')
            en

            let b:fugitive_files = {'Staged': {}, 'Unstaged': {}}
            let [staged, unstaged, untracked] = [[], [], []]
            let props = {}

            let pull = ''
            if empty(s:Tree())
                let branch = FugitiveHead(0)
                let head = FugitiveHead(11)
            elseif fugitive#GitVersion(2, 11)
                let cmd += ['status', '--porcelain=v2', '-bz']
                let [output, message, exec_error] = s:NullError(cmd)
                if exec_error
                    throw 'fugitive: ' . message
                en

                let i = 0
                while i < len(output)
                    let line = output[i]
                    let prop = matchlist(line, '# \(\S\+\) \(.*\)')
                    if len(prop)
                        let props[prop[1]] = prop[2]
                    elseif line[0] ==# '?'
                        call add(untracked, {'type': 'File', 'status': line[0], 'filename': line[2:-1], 'relative': [line[2:-1]]})
                    elseif line[0] !=# '#'
                        if line[0] ==# 'u'
                            let file = matchstr(line, '^.\{37\} \x\{40,\} \x\{40,\} \x\{40,\} \zs.*$')
                        el
                            let file = matchstr(line, '^.\{30\} \x\{40,\} \x\{40,\} \zs.*$')
                        en
                        if line[0] ==# '2'
                            let i += 1
                            let file = matchstr(file, ' \zs.*')
                            let relative = [file, output[i]]
                        el
                            let relative = [file]
                        en
                        let filename = join(reverse(copy(relative)), ' -> ')
                        let sub = matchstr(line, '^[12u] .. \zs....')
                        if line[2] !=# '.'
                            call add(staged, {'type': 'File', 'status': line[2], 'filename': filename, 'relative': relative, 'submodule': sub})
                        en
                        if line[3] !=# '.'
                            let sub = matchstr(line, '^[12u] .. \zs....')
                            call add(unstaged, {'type': 'File', 'status': get({'C':'M','M':'?','U':'?'}, matchstr(sub, 'S\.*\zs[CMU]'), line[3]), 'filename': file, 'relative': [file], 'submodule': sub})
                        en
                    en
                    let i += 1
                endwhile
                let branch = substitute(get(props, 'branch.head', '(unknown)'), '\C^(\%(detached\|unknown\))$', '', '')
                if len(branch)
                    let head = branch
                elseif has_key(props, 'branch.oid')
                    let head = props['branch.oid'][0:10]
                el
                    let head = FugitiveHead(11)
                en
                let pull = get(props, 'branch.upstream', '')
            el " git < 2.11
                let cmd += ['status', '--porcelain', '-bz']
                let [output, message, exec_error] = s:NullError(cmd)
                if exec_error
                    throw 'fugitive: ' . message
                en

                while get(output, 0, '') =~# '^\l\+:'
                    call remove(output, 0)
                endwhile
                let head = matchstr(output[0], '^## \zs\S\+\ze\%($\| \[\)')
                if head =~# '\.\.\.'
                    let [head, pull] = split(head, '\.\.\.')
                    let branch = head
                elseif head ==# 'HEAD' || empty(head)
                    let head = FugitiveHead(11)
                    let branch = ''
                el
                    let branch = head
                en

                let i = 0
                while i < len(output)
                    let line = output[i]
                    let file = line[3:-1]
                    let i += 1
                    if line[2] !=# ' '
                        continue
                    en
                    if line[0:1] =~# '[RC]'
                        let relative = [file, output[i]]
                        let i += 1
                    el
                        let relative = [file]
                    en
                    let filename = join(reverse(copy(relative)), ' -> ')
                    if line[0] !~# '[ ?!#]'
                        call add(staged, {'type': 'File', 'status': line[0], 'filename': filename, 'relative': relative, 'submodule': ''})
                    en
                    if line[0:1] ==# '??'
                        call add(untracked, {'type': 'File', 'status': line[1], 'filename': filename, 'relative': relative})
                    elseif line[1] !~# '[ !#]'
                        call add(unstaged, {'type': 'File', 'status': line[1], 'filename': file, 'relative': [file], 'submodule': ''})
                    en
                endwhile
            en

            let diff = {'Staged': {'stdout': ['']}, 'Unstaged': {'stdout': ['']}}
            if len(staged)
                let diff['Staged'] =
                        \ fugitive#Execute(['-c', 'diff.suppressBlankEmpty=false', 'diff', '--color=never', '--no-ext-diff', '--no-prefix', '--cached'], function('len'))
            en
            if len(unstaged)
                let diff['Unstaged'] =
                        \ fugitive#Execute(['-c', 'diff.suppressBlankEmpty=false', 'diff', '--color=never', '--no-ext-diff', '--no-prefix'], function('len'))
            en

            for dict in staged
                let b:fugitive_files['Staged'][dict.filename] = dict
            endfor
            for dict in unstaged
                let b:fugitive_files['Unstaged'][dict.filename] = dict
            endfor

            let pull_type = 'Pull'
            if len(pull)
                let rebase = FugitiveConfigGet('branch.' . branch . '.rebase', config)
                if empty(rebase)
                    let rebase = FugitiveConfigGet('pull.rebase', config)
                en
                if rebase =~# '^\%(true\|yes\|on\|1\|interactive\|merges\|preserve\)$'
                    let pull_type = 'Rebase'
                elseif rebase =~# '^\%(false\|no|off\|0\|\)$'
                    let pull_type = 'Merge'
                en
            en

            let push_remote = FugitiveConfigGet('branch.' . branch . '.pushRemote', config)
            if empty(push_remote)
                let push_remote = FugitiveConfigGet('remote.pushDefault', config)
            en
            let fetch_remote = FugitiveConfigGet('branch.' . branch . '.remote', config)
            if empty(fetch_remote)
                let fetch_remote = 'origin'
            en
            if empty(push_remote)
                let push_remote = fetch_remote
            en

            let push_default = FugitiveConfigGet('push.default', config)
            if empty(push_default)
                let push_default = fugitive#GitVersion(2) ? 'simple' : 'matching'
            en
            if push_default ==# 'upstream'
                let push = pull
            el
                let push = len(branch) ? (push_remote ==# '.' ? '' : push_remote . '/') . branch : ''
            en

            if isdirectory(fugitive#Find('.git/rebase-merge/'))
                let rebasing_dir = fugitive#Find('.git/rebase-merge/')
            elseif isdirectory(fugitive#Find('.git/rebase-apply/'))
                let rebasing_dir = fugitive#Find('.git/rebase-apply/')
            en

            let rebasing = []
            let rebasing_head = 'detached HEAD'
            if exists('rebasing_dir') && filereadable(rebasing_dir . 'git-rebase-todo')
                let rebasing_head = substitute(readfile(rebasing_dir . 'head-name')[0], '\C^refs/heads/', '', '')
                let len = 11
                let lines = readfile(rebasing_dir . 'git-rebase-todo')
                for line in lines
                    let hash = matchstr(line, '^[^a-z].*\s\zs[0-9a-f]\{4,\}\ze\.\.')
                    if len(hash)
                        let len = len(hash)
                        break
                    en
                endfor
                if getfsize(rebasing_dir . 'done') > 0
                    let done = readfile(rebasing_dir . 'done')
                    call map(done, 'substitute(v:val, ''^\l\+\>'', "done", "")')
                    let done[-1] = substitute(done[-1], '^\l\+\>', 'stop', '')
                    let lines = done + lines
                en
                call reverse(lines)
                for line in lines
                    let match = matchlist(line, '^\(\l\+\)\s\+\(\x\{4,\}\)\s\+\(.*\)')
                    if len(match) && match[1] !~# 'exec\|merge\|label'
                        call add(rebasing, {'type': 'Rebase', 'status': get(s:rebase_abbrevs, match[1], match[1]), 'commit': strpart(match[2], 0, len), 'subject': match[3]})
                    en
                endfor
            en

            let b:fugitive_diff = diff
            if get(a:, 1, v:cmdbang)
                unlet! b:fugitive_expanded
            en
            let expanded = get(b:, 'fugitive_expanded', {'Staged': {}, 'Unstaged': {}})
            let b:fugitive_expanded = {'Staged': {}, 'Unstaged': {}}

            silent keepjumps %delete_

            call s:AddHeader('Head', head)
            call s:AddHeader(pull_type, pull)
            if push !=# pull
                call s:AddHeader('Push', push)
            en
            if empty(s:Tree())
                if get(fugitive#ConfigGetAll('core.bare', config), 0, '') !~# '^\%(false\|no|off\|0\|\)$'
                    call s:AddHeader('Bare', 'yes')
                el
                    call s:AddHeader('Error', s:worktree_error)
                en
            en
            if get(fugitive#ConfigGetAll('advice.statusHints', config), 0, 'true') !~# '^\%(false\|no|off\|0\|\)$'
                call s:AddHeader('Help', 'g?')
            en

            call s:AddSection('Rebasing ' . rebasing_head, rebasing)
            call s:AddSection('Untracked', untracked)
            call s:AddSection('Unstaged', unstaged)
            let unstaged_end = len(unstaged) ? line('$') : 0
            call s:AddSection('Staged', staged)
            let staged_end = len(staged) ? line('$') : 0

            if len(push) && !(push ==# pull && get(props, 'branch.ab') =~# '^+0 ')
                call s:AddLogSection('Unpushed to ' . push, [push . '..' . head])
            en
            if len(pull) && push !=# pull
                call s:AddLogSection('Unpushed to ' . pull, [pull . '..' . head])
            en
            if empty(pull) && empty(push) && empty(rebasing)
                call s:AddLogSection('Unpushed to *', [head, '--not', '--remotes'])
            en
            if len(push) && push !=# pull
                call s:AddLogSection('Unpulled from ' . push, [head . '..' . push])
            en
            if len(pull) && get(props, 'branch.ab') !~# ' -0$'
                call s:AddLogSection('Unpulled from ' . pull, [head . '..' . pull])
            en

            setl  nomodified readonly noswapfile
            doautocmd BufReadPost
            setl  nomodifiable
            if &bufhidden ==# ''
                setl  bufhidden=delete
            en
            if !exists('b:dispatch')
                let b:dispatch = ':Git fetch --all'
            en
            call fugitive#MapJumps()
            call s:Map('n', '-', ":<C-U>execute <SID>Do('Toggle',0)<CR>", '<silent>')
            call s:Map('x', '-', ":<C-U>execute <SID>Do('Toggle',1)<CR>", '<silent>')
            call s:Map('n', 's', ":<C-U>execute <SID>Do('Stage',0)<CR>", '<silent>')
            call s:Map('x', 's', ":<C-U>execute <SID>Do('Stage',1)<CR>", '<silent>')
            call s:Map('n', 'u', ":<C-U>execute <SID>Do('Unstage',0)<CR>", '<silent>')
            call s:Map('x', 'u', ":<C-U>execute <SID>Do('Unstage',1)<CR>", '<silent>')
            call s:Map('n', 'U', ":<C-U>Git reset -q<CR>", '<silent>')
            call s:MapMotion('gu', "exe <SID>StageJump(v:count, 'Untracked', 'Unstaged')")
            call s:MapMotion('gU', "exe <SID>StageJump(v:count, 'Unstaged', 'Untracked')")
            call s:MapMotion('gs', "exe <SID>StageJump(v:count, 'Staged')")
            call s:MapMotion('gp', "exe <SID>StageJump(v:count, 'Unpushed')")
            call s:MapMotion('gP', "exe <SID>StageJump(v:count, 'Unpulled')")
            call s:MapMotion('gr', "exe <SID>StageJump(v:count, 'Rebasing')")
            call s:Map('n', 'C', ":echoerr 'fugitive: C has been removed in favor of cc'<CR>", '<silent><unique>')
            call s:Map('n', 'a', ":<C-U>execute <SID>Do('Toggle',0)<CR>", '<silent>')
            call s:Map('n', 'i', ":<C-U>execute <SID>NextExpandedHunk(v:count1)<CR>", '<silent>')
            call s:Map('n', "=", ":<C-U>execute <SID>StageInline('toggle',line('.'),v:count)<CR>", '<silent>')
            call s:Map('n', "<", ":<C-U>execute <SID>StageInline('hide',  line('.'),v:count)<CR>", '<silent>')
            call s:Map('n', ">", ":<C-U>execute <SID>StageInline('show',  line('.'),v:count)<CR>", '<silent>')
            call s:Map('x', "=", ":<C-U>execute <SID>StageInline('toggle',line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>", '<silent>')
            call s:Map('x', "<", ":<C-U>execute <SID>StageInline('hide',  line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>", '<silent>')
            call s:Map('x', ">", ":<C-U>execute <SID>StageInline('show',  line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>", '<silent>')
            call s:Map('n', 'D', ":echoerr 'fugitive: D has been removed in favor of dd'<CR>", '<silent><unique>')
            call s:Map('n', 'dd', ":<C-U>execute <SID>StageDiff('Gdiffsplit')<CR>", '<silent>')
            call s:Map('n', 'dh', ":<C-U>execute <SID>StageDiff('Ghdiffsplit')<CR>", '<silent>')
            call s:Map('n', 'ds', ":<C-U>execute <SID>StageDiff('Ghdiffsplit')<CR>", '<silent>')
            call s:Map('n', 'dp', ":<C-U>execute <SID>StageDiffEdit()<CR>", '<silent>')
            call s:Map('n', 'dv', ":<C-U>execute <SID>StageDiff('Gvdiffsplit')<CR>", '<silent>')
            call s:Map('n', 'd?', ":<C-U>help fugitive_d<CR>", '<silent>')
            call s:Map('n', 'P', ":<C-U>execute <SID>StagePatch(line('.'),line('.')+v:count1-1)<CR>", '<silent>')
            call s:Map('x', 'P', ":<C-U>execute <SID>StagePatch(line(\"'<\"),line(\"'>\"))<CR>", '<silent>')
            call s:Map('n', 'p', ":<C-U>if v:count<Bar>silent exe <SID>GF('pedit')<Bar>else<Bar>echoerr 'Use = for inline diff, P for :Git add/reset --patch, 1p for :pedit'<Bar>endif<CR>", '<silent>')
            call s:Map('x', 'p', ":<C-U>execute <SID>StagePatch(line(\"'<\"),line(\"'>\"))<CR>", '<silent>')
            call s:Map('n', 'I', ":<C-U>execute <SID>StagePatch(line('.'),line('.'))<CR>", '<silent>')
            call s:Map('x', 'I', ":<C-U>execute <SID>StagePatch(line(\"'<\"),line(\"'>\"))<CR>", '<silent>')
            call s:Map('n', 'gq', ":<C-U>if bufnr('$') == 1<Bar>quit<Bar>else<Bar>bdelete<Bar>endif<CR>", '<silent>')
            call s:Map('n', 'R', ":echohl WarningMsg<Bar>echo 'Reloading is automatic.  Use :e to force'<Bar>echohl NONE<CR>", '<silent>')
            call s:Map('n', 'g<Bar>', ":<C-U>echoerr 'Changed to X'<CR>", '<silent><unique>')
            call s:Map('x', 'g<Bar>', ":<C-U>echoerr 'Changed to X'<CR>", '<silent><unique>')
            call s:Map('n', 'X', ":<C-U>execute <SID>StageDelete(line('.'), 0, v:count)<CR>", '<silent>')
            call s:Map('x', 'X', ":<C-U>execute <SID>StageDelete(line(\"'<\"), line(\"'>\"), v:count)<CR>", '<silent>')
            call s:Map('n', 'gI', ":<C-U>execute <SID>StageIgnore(line('.'), line('.'), v:count)<CR>", '<silent>')
            call s:Map('x', 'gI', ":<C-U>execute <SID>StageIgnore(line(\"'<\"), line(\"'>\"), v:count)<CR>", '<silent>')
            call s:Map('n', '.', ':<C-U> <C-R>=<SID>StageArgs(0)<CR><Home>')
            call s:Map('x', '.', ':<C-U> <C-R>=<SID>StageArgs(1)<CR><Home>')
            setl  filetype=fugitive

            for [lnum, section] in [[staged_end, 'Staged'], [unstaged_end, 'Unstaged']]
                while len(getline(lnum))
                    let filename = matchstr(getline(lnum), '^[A-Z?] \zs.*')
                    if has_key(expanded[section], filename)
                        call s:StageInline('show', lnum)
                    en
                    let lnum -= 1
                endwhile
            endfor

            let b:fugitive_reltime = reltime()
            return s:DoAutocmd('User FugitiveIndex')
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        finally
            let b:fugitive_type = 'index'
        endtry
    endf

    fun! fugitive#FileReadCmd(...) abort
        let amatch = a:0 ? a:1 : expand('<amatch>')
        let [dir, rev] = s:DirRev(amatch)
        let line = a:0 > 1 ? a:2 : line("'[")
        if empty(dir)
            return 'noautocmd ' . line . 'read ' . s:fnameescape(amatch)
        en
        if rev !~# ':' && s:ChompDefault('', [dir, 'cat-file', '-t', rev]) =~# '^\%(commit\|tag\)$'
            let cmd = [dir, 'log', '--pretty=format:%B', '-1', rev, '--']
        el
            let cmd = [dir, 'cat-file', '-p', rev, '--']
        en
        let temp = tempname()
        let [err, exec_error] = s:StdoutToFile(temp, cmd)
        if exec_error
            call delete(temp)
            return 'noautocmd ' . line . 'read ' . s:fnameescape(amatch)
        el
            return 'silent keepalt ' . line . 'read ' . s:fnameescape(temp) . '|call delete(' . string(temp) . ')'
        en
    endf

    fun! fugitive#FileWriteCmd(...) abort
        let temp = tempname()
        let amatch = a:0 ? a:1 : expand('<amatch>')
        let autype = a:0 > 1 ? 'Buf' : 'File'
        if exists('#' . autype . 'WritePre')
            exe  s:DoAutocmd(autype . 'WritePre ' . s:fnameescape(amatch))
        en
        try
            let [dir, commit, file] = s:DirCommitFile(amatch)
            if commit !~# '^[0-3]$' || !v:cmdbang && (line("'[") != 1 || line("']") != line('$'))
                return "noautocmd '[,']write" . (v:cmdbang ? '!' : '') . ' ' . s:fnameescape(amatch)
            en
            silent execute "noautocmd keepalt '[,']write ".temp
            let hash = s:TreeChomp([dir, '--literal-pathspecs', 'hash-object', '-w', '--', FugitiveGitPath(temp)])
            let old_mode = matchstr(s:ChompDefault('', ['ls-files', '--stage', '.' . file], dir), '^\d\+')
            if empty(old_mode)
                let old_mode = executable(s:Tree(dir) . file) ? '100755' : '100644'
            en
            let error = s:UpdateIndex(dir, [old_mode, hash, commit, file[1:-1]])
            if empty(error)
                setl  nomodified
                if exists('#' . autype . 'WritePost')
                    exe  s:DoAutocmd(autype . 'WritePost ' . s:fnameescape(amatch))
                en
                exe s:DoAutocmdChanged(dir)
                return ''
            el
                return 'echoerr '.string('fugitive: '.error)
            en
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        finally
            call delete(temp)
        endtry
    endf

    fun! fugitive#BufReadCmd(...) abort
        let amatch = a:0 ? a:1 : expand('<amatch>')
        try
            let [dir, rev] = s:DirRev(amatch)
            if empty(dir)
                return 'echo "Invalid Fugitive URL"'
            en
            let b:git_dir = s:GitDir(dir)
            if rev =~# '^:\d$'
                let b:fugitive_type = 'stage'
            el
                let r = fugitive#Execute([dir, 'cat-file', '-t', rev])
                let b:fugitive_type = get(r.stdout, 0, '')
                if r.exit_status && rev =~# '^:0'
                    let r = fugitive#Execute([dir, 'write-tree', '--prefix=' . rev[3:-1]])
                    let sha = get(r.stdout, 0, '')
                    let b:fugitive_type = 'tree'
                en
                if r.exit_status
                    let error = substitute(join(r.stderr, "\n"), "\n*$", '', '')
                    unlet b:fugitive_type
                    setl  noswapfile
                    if empty(&bufhidden)
                        setl  bufhidden=delete
                    en
                    if rev =~# '^:\d:'
                        let &l:readonly = !filewritable(fugitive#Find('.git/index', dir))
                        return 'doautocmd BufNewFile'
                    el
                        setl  readonly nomodifiable
                        return 'doautocmd BufNewFile|echo ' . string(error)
                    en
                elseif b:fugitive_type !~# '^\%(tag\|commit\|tree\|blob\)$'
                    return "echoerr ".string("fugitive: unrecognized git type '".b:fugitive_type."'")
                en
                if !exists('b:fugitive_display_format') && b:fugitive_type != 'blob'
                    let b:fugitive_display_format = +getbufvar('#','fugitive_display_format')
                en
            en

            if b:fugitive_type !=# 'blob'
                setl  nomodeline
            en

            setl  noreadonly modifiable
            let pos = getpos('.')
            silent keepjumps %delete_
            setl  endofline

            let events = ['User FugitiveObject', 'User Fugitive' . substitute(b:fugitive_type, '^\l', '\u&', '')]

            try
                if b:fugitive_type !=# 'blob'
                    setl  foldmarker=<<<<<<<<,>>>>>>>>
                en
                exe s:DoAutocmd('BufReadPre')
                if b:fugitive_type ==# 'tree'
                    let b:fugitive_display_format = b:fugitive_display_format % 2
                    if b:fugitive_display_format
                        call s:ReplaceCmd([dir, 'ls-tree', exists('sha') ? sha : rev])
                    el
                        if !exists('sha')
                            let sha = s:TreeChomp(dir, 'rev-parse', '--verify', rev, '--')
                        en
                        call s:ReplaceCmd([dir, 'show', '--no-color', sha])
                    en
                elseif b:fugitive_type ==# 'tag'
                    let b:fugitive_display_format = b:fugitive_display_format % 2
                    if b:fugitive_display_format
                        call s:ReplaceCmd([dir, 'cat-file', b:fugitive_type, rev])
                    el
                        call s:ReplaceCmd([dir, 'cat-file', '-p', rev])
                    en
                elseif b:fugitive_type ==# 'commit'
                    let b:fugitive_display_format = b:fugitive_display_format % 2
                    if b:fugitive_display_format
                        call s:ReplaceCmd([dir, 'cat-file', b:fugitive_type, rev])
                    el
                        call s:ReplaceCmd([dir, '-c', 'diff.noprefix=false', '-c', 'log.showRoot=false', 'show', '--no-color', '-m', '--first-parent', '--pretty=format:tree%x20%T%nparent%x20%P%nauthor%x20%an%x20<%ae>%x20%ad%ncommitter%x20%cn%x20<%ce>%x20%cd%nencoding%x20%e%n%n%s%n%n%b', rev])
                        keepjumps 1
                        keepjumps call search('^parent ')
                        if getline('.') ==# 'parent '
                            silent lockmarks keepjumps delete_
                        el
                            silent exe (exists(':keeppatterns') ? 'keeppatterns' : '') 'keepjumps s/\m\C\%(^parent\)\@<! /\rparent /e' . (&gdefault ? '' : 'g')
                        en
                        keepjumps let lnum = search('^encoding \%(<unknown>\)\=$','W',line('.')+3)
                        if lnum
                            silent lockmarks keepjumps delete_
                        end
                        silent exe (exists(':keeppatterns') ? 'keeppatterns' : '') 'keepjumps 1,/^diff --git\|\%$/s/\r$//e'
                        keepjumps 1
                    en
                elseif b:fugitive_type ==# 'stage'
                    call s:ReplaceCmd([dir, 'ls-files', '--stage'])
                elseif b:fugitive_type ==# 'blob'
                    let blob_or_filters = rev =~# ':' && fugitive#GitVersion(2, 11) ? '--filters' : 'blob'
                    call s:ReplaceCmd([dir, 'cat-file', blob_or_filters, rev])
                en
            finally
                keepjumps call setpos('.',pos)
                setl  nomodified noswapfile
                let modifiable = rev =~# '^:.:' && b:fugitive_type !=# 'tree'
                if modifiable
                    let events = ['User FugitiveStageBlob']
                en
                let &l:readonly = !modifiable || !filewritable(fugitive#Find('.git/index', dir))
                if empty(&bufhidden)
                    setl  bufhidden=delete
                en
                let &l:modifiable = modifiable
                if b:fugitive_type !=# 'blob'
                    setl  filetype=git
                    call s:Map('n', 'a', ":<C-U>let b:fugitive_display_format += v:count1<Bar>exe fugitive#BufReadCmd(@%)<CR>", '<silent>')
                    call s:Map('n', 'i', ":<C-U>let b:fugitive_display_format -= v:count1<Bar>exe fugitive#BufReadCmd(@%)<CR>", '<silent>')
                en
                call fugitive#MapJumps()
            endtry

            setl  modifiable

            return s:DoAutocmd('BufReadPost') .
                        \ (modifiable ? '' : '|setl nomodifiable') . '|' .
                        \ call('s:DoAutocmd', events)
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
    endf

    fun! fugitive#BufWriteCmd(...) abort
        return fugitive#FileWriteCmd(a:0 ? a:1 : expand('<amatch>'), 1)
    endf

    fun! fugitive#SourceCmd(...) abort
        let amatch = a:0 ? a:1 : expand('<amatch>')
        let temp = s:BlobTemp(amatch)
        if empty(temp)
            return 'noautocmd source ' . s:fnameescape(amatch)
        en
        if !exists('g:virtual_scriptnames')
            let g:virtual_scriptnames = {}
        en
        let g:virtual_scriptnames[temp] = amatch
        return 'source ' . s:fnameescape(temp)
    endf

" Section: Temp files

    if !exists('s:temp_files')
        let s:temp_files = {}
    en

    fun! s:TempState(...) abort
        return get(s:temp_files, s:cpath(s:AbsoluteVimPath(a:0 ? a:1 : -1)), {})
    endf

    fun! fugitive#Result(...) abort
        if !a:0 && exists('g:fugitive_event')
            return get(g:, 'fugitive_result', {})
        elseif !a:0 || type(a:1) == type('') && a:1 =~# '^-\=$'
            return get(g:, '_fugitive_last_job', {})
        elseif type(a:1) == type(0)
            return s:TempState(a:1)
        elseif type(a:1) == type('')
            return s:TempState(a:1)
        elseif type(a:1) == type({}) && has_key(a:1, 'file')
            return s:TempState(a:1.file)
        el
            return {}
        en
    endf

    fun! s:TempDotMap() abort
        let cfile = s:cfile()
        if empty(cfile)
            if getline('.') =~# '^[*+] \+\f' && col('.') < 2
                return matchstr(getline('.'), '^. \+\zs\f\+')
            el
                return expand('<cfile>')
            en
        en
        let name = fugitive#Find(cfile[0])
        let [dir, commit, file] = s:DirCommitFile(name)
        if len(commit) && empty(file)
            return commit
        elseif s:cpath(s:Tree(), getcwd())
            return fugitive#Path(name, "./")
        el
            return fugitive#Real(name)
        en
    endf

    fun! s:TempReadPre(file) abort
        let key = s:cpath(s:AbsoluteVimPath(a:file))
        if has_key(s:temp_files, key)
            let dict = s:temp_files[key]
            setl  nomodeline
            if empty(&bufhidden)
                setl  bufhidden=delete
            en
            setl  buftype=nowrite
            setl  nomodifiable
            let b:git_dir = dict.git_dir
            if len(dict.git_dir)
                call extend(b:, {'fugitive_type': 'temp'}, 'keep')
            en
        en
        return ''
    endf

    fun! s:TempReadPost(file) abort
        let key = s:cpath(s:AbsoluteVimPath(a:file))
        if has_key(s:temp_files, key)
            let dict = s:temp_files[key]
            if !has_key(dict, 'job')
                setl  nobuflisted
            en
            if get(dict, 'filetype', '') ==# 'git'
                call fugitive#MapJumps()
                call s:Map('n', '.', ":<C-U> <C-R>=<SID>fnameescape(<SID>TempDotMap())<CR><Home>")
                call s:Map('x', '.', ":<C-U> <C-R>=<SID>fnameescape(<SID>TempDotMap())<CR><Home>")
            en
            if has_key(dict, 'filetype')
                if dict.filetype ==# 'man' && has('nvim')
                    let b:man_sect = matchstr(getline(1), '^\w\+(\zs\d\+\ze)')
                en
                if !get(g:, 'did_load_ftplugin') && dict.filetype ==# 'fugitiveblame'
                    call s:BlameMaps(0)
                en
                let &l:filetype = dict.filetype
            en
            setl  foldmarker=<<<<<<<<,>>>>>>>>
            if !&modifiable
                call s:Map('n', 'gq', ":<C-U>bdelete<CR>", '<silent> <unique>')
            en
        en
        return s:DoAutocmd('User FugitivePager')
    endf

    fun! s:TempDelete(file) abort
        let key = s:cpath(s:AbsoluteVimPath(a:file))
        if has_key(s:temp_files, key) && !has_key(s:temp_files[key], 'job') && key !=# s:cpath(get(get(g:, '_fugitive_last_job', {}), 'file', ''))
            call delete(a:file)
            call remove(s:temp_files, key)
        en
        return ''
    endf

    aug  fugitive_temp
        au!
        au BufReadPre  * exe s:TempReadPre( +expand('<abuf>'))
        au BufReadPost * exe s:TempReadPost(+expand('<abuf>'))
        au BufWipeout  * exe s:TempDelete(  +expand('<abuf>'))
    aug  END

" Section: :Git

    fun! s:AskPassArgs(dir) abort
        if (len($DISPLAY) || len($TERM_PROGRAM) || has('gui_running')) &&
                    \ empty($GIT_ASKPASS) && empty($SSH_ASKPASS) && empty(fugitive#ConfigGetAll('core.askpass', a:dir))
            if s:executable(FugitiveVimPath(s:ExecPath() . '/git-gui--askpass'))
                return ['-c', 'core.askPass=' . s:ExecPath() . '/git-gui--askpass']
            elseif s:executable('ssh-askpass')
                return ['-c', 'core.askPass=ssh-askpass']
            en
        en
        return []
    endf

    fun! s:RunSave(state) abort
        let s:temp_files[s:cpath(a:state.file)] = a:state
    endf

    fun! s:RunFinished(state, ...) abort
        if has_key(get(g:, '_fugitive_last_job', {}), 'file') && bufnr(g:_fugitive_last_job.file) < 0
            exe s:TempDelete(remove(g:, '_fugitive_last_job').file)
        en
        let g:_fugitive_last_job = a:state
        let first = join(readfile(a:state.file, '', 2), "\n")
        if get(a:state, 'filetype', '') ==# 'git' && first =~# '\<\([[:upper:][:digit:]_-]\+(\d\+)\).*\1'
            let a:state.filetype = 'man'
        en
        if !has_key(a:state, 'capture_bufnr')
            return
        en
        call fugitive#DidChange(a:state)
    endf

    fun! s:RunEdit(state, tmp, job) abort
        if get(a:state, 'request', '') !=# 'edit'
            return 0
        en
        call remove(a:state, 'request')
        let sentinel = a:state.file . '.edit'
        let file = FugitiveVimPath(readfile(sentinel, '', 1)[0])
        try
            if !&equalalways && a:state.mods !~# '\<tab\>' && 3 > (a:state.mods =~# '\<vert' ? winwidth(0) : winheight(0))
                let noequalalways = 1
                setglobal equalalways
            en
            exe substitute(a:state.mods, '\<tab\>', '-tab', 'g') 'keepalt split' s:fnameescape(file)
        finally
            if exists('l:noequalalways')
                setglobal noequalalways
            en
        endtry
        set bufhidden=wipe
        let bufnr = bufnr('')
        let s:edit_jobs[bufnr] = [a:state, a:tmp, a:job, sentinel]
        call fugitive#DidChange(a:state.git_dir)
        if bufnr == bufnr('') && !exists('g:fugitive_event')
            try
                let g:fugitive_event = a:state.git_dir
                let g:fugitive_result = a:state
                exe s:DoAutocmd('User FugitiveEditor')
            finally
                unlet! g:fugitive_event g:fugitive_result
            endtry
        en
        return 1
    endf

    fun! s:RunReceive(state, tmp, type, job, data, ...) abort
        if a:type ==# 'err' || a:state.pty
            let data = type(a:data) == type([]) ? join(a:data, "\n") : a:data
            let data = a:tmp.escape . data
            let escape = "\033]51;[^\007]*"
            let a:tmp.escape = matchstr(data, escape . '$')
            if len(a:tmp.escape)
                let data = strpart(data, 0, len(data) - len(a:tmp.escape))
            en
            let cmd = matchstr(data, escape . "\007")[5:-2]
            let data = substitute(data, escape . "\007", '', 'g')
            if cmd =~# '^fugitive:'
                let a:state.request = strpart(cmd, 9)
            en
            let lines = split(a:tmp.err . data, "\r\\=\n", 1)
            let a:tmp.err = lines[-1]
            let lines[-1] = ''
            call map(lines, 'substitute(v:val, ".*\r", "", "")')
        el
            let lines = type(a:data) == type([]) ? a:data : split(a:data, "\n", 1)
            if len(a:tmp.out)
                let lines[0] = a:tmp.out . lines[0]
            en
            let a:tmp.out = lines[-1]
            let lines[-1] = ''
        en
        call writefile(lines, a:state.file, 'ba')
        if has_key(a:tmp, 'echo')
            if !exists('l:data')
                let data = type(a:data) == type([]) ? join(a:data, "\n") : a:data
            en
            let a:tmp.echo .= data
        en
        let line_count = a:tmp.line_count
        let a:tmp.line_count += len(lines) - 1
        if !has_key(a:state, 'capture_bufnr') || !bufloaded(a:state.capture_bufnr)
            return
        en
        call remove(lines, -1)
        try
            call setbufvar(a:state.capture_bufnr, '&modifiable', 1)
            if !line_count && len(lines) > 1000
                let first = remove(lines, 0, 999)
                call setbufline(a:state.capture_bufnr, 1, first)
                redraw
                call setbufline(a:state.capture_bufnr, 1001, lines)
            el
                call setbufline(a:state.capture_bufnr, line_count + 1, lines)
            en
            call setbufvar(a:state.capture_bufnr, '&modifiable', 0)
            if !a:state.pager && getwinvar(bufwinid(a:state.capture_bufnr), '&previewwindow')
                let winnr = bufwinnr(a:state.capture_bufnr)
                if winnr > 0
                    let old_winnr = winnr()
                    exe 'noautocmd' winnr.'wincmd w'
                    $
                    exe 'noautocmd' old_winnr.'wincmd w'
                en
            en
        catch
        endtry
    endf

    fun! s:RunExit(state, tmp, job, exit_status) abort
        let a:state.exit_status = a:exit_status
        if has_key(a:state, 'job')
            return
        en
        call s:RunFinished(a:state)
    endf

    fun! s:RunClose(state, tmp, job, ...) abort
        if a:0
            call s:RunExit(a:state, a:tmp, a:job, a:1)
        en
        let noeol = substitute(substitute(a:tmp.err, "\r$", '', ''), ".*\r", '', '') . a:tmp.out
        call writefile([noeol], a:state.file, 'ba')
        call remove(a:state, 'job')
        if has_key(a:state, 'capture_bufnr') && bufloaded(a:state.capture_bufnr)
            if len(noeol)
                call setbufvar(a:state.capture_bufnr, '&modifiable', 1)
                call setbufline(a:state.capture_bufnr, a:tmp.line_count + 1, [noeol])
                call setbufvar(a:state.capture_bufnr, '&eol', 0)
                call setbufvar(a:state.capture_bufnr, '&modifiable', 0)
            en
            call setbufvar(a:state.capture_bufnr, '&modified', 0)
            call setbufvar(a:state.capture_bufnr, '&buflisted', 0)
            if a:state.filetype !=# getbufvar(a:state.capture_bufnr, '&filetype', '')
                call setbufvar(a:state.capture_bufnr, '&filetype', a:state.filetype)
            en
        en
        if !has_key(a:state, 'exit_status')
            return
        en
        call s:RunFinished(a:state)
    endf

    fun! s:RunSend(job, str) abort
        try
            if type(a:job) == type(0)
                call chansend(a:job, a:str)
            el
                call ch_sendraw(a:job, a:str)
            en
            return len(a:str)
        catch /^Vim\%((\a\+)\)\=:E90[06]:/
            return 0
        endtry
    endf

    fun! s:RunCloseIn(job) abort
        try
            if type(a:job) ==# type(0)
                call chanclose(a:job, 'stdin')
            el
                call ch_close_in(a:job)
            en
            return 1
        catch /^Vim\%((\a\+)\)\=:E90[06]:/
            return 0
        endtry
    endf

    fun! s:RunEcho(tmp) abort
        if !has_key(a:tmp, 'echo')
            return
        en
        let data = a:tmp.echo
        let a:tmp.echo = matchstr(data, "[\r\n]\\+$")
        if len(a:tmp.echo)
            let data = strpart(data, 0, len(data) - len(a:tmp.echo))
        en
        echon substitute(data, "\r\\ze\n", '', 'g')
    endf

    fun! s:RunTick(job) abort
        if type(a:job) == v:t_number
            return jobwait([a:job], 1)[0] == -1
        elseif type(a:job) == 8
            let running = ch_status(a:job) !~# '^closed$\|^failed$' || job_status(a:job) ==# 'run'
            sleep 1m
            return running
        en
    endf

    if !exists('s:edit_jobs')
        let s:edit_jobs = {}
    en
    fun! s:RunWait(state, tmp, job, ...) abort
        if a:0 && filereadable(a:1)
            call delete(a:1)
        en
        try
            if a:tmp.no_more && &more
                let more = &more
                let &more = 0
            en
            while get(a:state, 'request', '') !=# 'edit' && s:RunTick(a:job)
                call s:RunEcho(a:tmp)
                if !get(a:tmp, 'closed_in')
                    let peek = getchar(1)
                    if peek != 0 && !(has('win32') && peek == 128)
                        let c = getchar()
                        let c = type(c) == type(0) ? nr2char(c) : c
                        if c ==# "\<C-D>" || c ==# "\<Esc>"
                            let a:tmp.closed_in = 1
                            let can_pedit = s:RunCloseIn(a:job) && exists('*setbufline')
                            for winnr in range(1, winnr('$'))
                                if getwinvar(winnr, '&previewwindow') && getbufvar(winbufnr(winnr), '&modified')
                                    let can_pedit = 0
                                en
                            endfor
                            if can_pedit
                                if has_key(a:tmp, 'echo')
                                    call remove(a:tmp, 'echo')
                                en
                                call writefile(['fugitive: aborting edit due to background operation.'], a:state.file . '.exit')
                                exe (&splitbelow ? 'botright' : 'topleft') 'silent pedit ++ff=unix' s:fnameescape(a:state.file)
                                let a:state.capture_bufnr = bufnr(a:state.file)
                                call setbufvar(a:state.capture_bufnr, '&modified', 1)
                                let finished = 0
                                redraw!
                                return ''
                            en
                        el
                            call s:RunSend(a:job, c)
                            if !a:state.pty
                                echon c
                            en
                        en
                    en
                en
            endwhile
            if !has_key(a:state, 'request') && has_key(a:state, 'job') && exists('*job_status') && job_status(a:job) ==# "dead"
                throw 'fugitive: close callback did not fire; this should never happen'
            en
            call s:RunEcho(a:tmp)
            if has_key(a:tmp, 'echo')
                let a:tmp.echo = substitute(a:tmp.echo, "^\r\\=\n", '', '')
                echo
            en
            let finished = !s:RunEdit(a:state, a:tmp, a:job)
        finally
            if exists('l:more')
                let &more = more
            en
            if !exists('finished')
                try
                    if a:state.pty && !get(a:tmp, 'closed_in')
                        call s:RunSend(a:job, "\<C-C>")
                    elseif type(a:job) == type(0)
                        call jobstop(a:job)
                    el
                        call job_stop(a:job)
                    en
                catch /.*/
                endtry
            elseif finished
                call fugitive#DidChange(a:state)
            en
        endtry
        return ''
    endf

    if !exists('s:resume_queue')
        let s:resume_queue = []
    en
    fun! fugitive#Resume() abort
        while len(s:resume_queue)
            let enqueued = remove(s:resume_queue, 0)
            if enqueued[2] isnot# ''
                try
                    call call('s:RunWait', enqueued)
                endtry
            en
        endwhile
    endf

    fun! s:RunBufDelete(bufnr) abort
        let state = s:TempState(+a:bufnr)
        if has_key(state, 'job')
            try
                if type(state.job) == type(0)
                    call jobstop(state.job)
                el
                    call job_stop(state.job)
                en
            catch
            endtry
        en
        if has_key(s:edit_jobs, a:bufnr) |
            call add(s:resume_queue, remove(s:edit_jobs, a:bufnr))
            call feedkeys("\<C-\>\<C-N>:redraw!|call delete(" . string(s:resume_queue[-1][0].file . '.edit') .
                        \ ")|call fugitive#Resume()|checktime\r", 'n')
        en
    endf

    aug  fugitive_job
        au!
        au BufDelete * call s:RunBufDelete(+expand('<abuf>'))
        au VimLeave *
                    \ for s:jobbuf in keys(s:edit_jobs) |
                    \   call writefile(['Aborting edit due to Vim exit.'], s:edit_jobs[s:jobbuf][0].file . '.exit') |
                    \   redraw! |
                    \   call call('s:RunWait', remove(s:edit_jobs, s:jobbuf)) |
                    \ endfor
    aug  END

    fun! fugitive#CanPty() abort
        return get(g:, 'fugitive_pty_debug_override',
                    \ has('unix') && !has('win32unix') && (has('patch-8.0.0744') || has('nvim')) && fugitive#GitVersion() !~# '\.windows\>')
    endf

    fun! fugitive#PagerFor(argv, ...) abort
        let args = a:argv
        if empty(args)
            return 0
        elseif (args[0] ==# 'help' || get(args, 1, '') ==# '--help') && !s:HasOpt(args, '--web')
            return 1
        en
        if args[0] ==# 'config' && (s:HasOpt(args, '-e', '--edit') ||
                    \   !s:HasOpt(args, '--list', '--get-all', '--get-regexp', '--get-urlmatch')) ||
                    \ args[0] =~# '^\%(tag\|branch\)$' && (
                    \    s:HasOpt(args, '--edit-description', '--unset-upstream', '-m', '-M', '--move', '-c', '-C', '--copy', '-d', '-D', '--delete') ||
                    \   len(filter(args[1:-1], 'v:val =~# "^[^-]\\|^--set-upstream-to="')) &&
                    \   !s:HasOpt(args, '--contains', '--no-contains', '--merged', '--no-merged', '--points-at'))
            return 0
        en
        let config = a:0 ? a:1 : fugitive#Config()
        let value = get(fugitive#ConfigGetAll('pager.' . args[0], config), 0, -1)
        if value =~# '^\%(true\|yes\|on\|1\)$'
            return 1
        elseif value =~# '^\%(false\|no|off\|0\|\)$'
            return 0
        elseif type(value) == type('')
            return value
        elseif args[0] =~# '^\%(branch\|config\|diff\|grep\|log\|range-diff\|shortlog\|show\|tag\|whatchanged\)$' ||
                    \ (args[0] ==# 'stash' && get(args, 1, '') ==# 'show') ||
                    \ (args[0] ==# 'reflog' && get(args, 1, '') !~# '^\%(expire\|delete\|exists\)$') ||
                    \ (args[0] ==# 'am' && s:HasOpt(args, '--show-current-patch'))
            return 1
        el
            return 0
        en
    endf

    let s:disable_colors = []
    for s:colortype in ['advice', 'branch', 'diff', 'grep', 'interactive', 'pager', 'push', 'remote', 'showBranch', 'status', 'transport', 'ui']
        call extend(s:disable_colors, ['-c', 'color.' . s:colortype . '=false'])
    endfor
    unlet s:colortype
    fun! fugitive#Command(line1, line2, range, bang, mods, arg) abort
        exe s:VersionCheck()
        let dir = s:Dir()
        if len(dir)  | exe s:DirCheck(dir)  | endif
        let config = copy(fugitive#Config(dir))
        let curwin = a:arg =~#   '^++curwin\>' || !a:line2
        let [args, after] = s:SplitExpandChain(  substitute(a:arg, '^++curwin\>\s*', '', ''), s:Tree(dir) )
        let flags = []
        let pager = -1
        let explicit_pathspec_option = 0
        while len(args)
            if args[0] ==# '-c' && len(args) > 1
                call extend(flags, remove(args, 0, 1))
            elseif args[0] =~# '^-p$\|^--paginate$'
                let pager = 2
                call remove(args, 0)
            elseif args[0] =~# '^-P$\|^--no-pager$'
                let pager = 0
                call remove(args, 0)
            elseif args[0] =~# '^--\%([[:lower:]-]\+-pathspecs\)$'
                let explicit_pathspec_option = 1
                call add(flags, remove(args, 0))
            elseif args[0] =~# '^\%(--no-optional-locks\)$'
                call add(flags, remove(args, 0))
            elseif args[0] =~# '^-C$\|^--\%(exec-path=\|git-dir=\|work-tree=\|bare$\)'
                return 'echoerr ' . string('fugitive: ' . args[0] . ' is not supported')
            el
                break
            en
        endwhile
        if !explicit_pathspec_option
            call insert(flags, '--no-literal-pathspecs')
        en
        let no_pager = pager is# 0
        if no_pager
            call add(flags, '--no-pager')
        en
        let env = {}
        let i = 0
        while i < len(flags) - 1
            if flags[i] ==# '-c'
                let i += 1
                let config_name = tolower(matchstr(flags[i], '^[^=]\+'))
                if has_key(s:prepare_env, config_name) && flags[i] =~# '=.'
                    let env[s:prepare_env[config_name]] = matchstr(flags[i], '=\zs.*')
                en
                if flags[i] =~# '='
                    let config[config_name] = [matchstr(flags[i], '=\zs.*')]
                el
                    let config[config_name] = [1]
                en
            en
            let i += 1
        endwhile
        let options = {'git': s:UserCommandList(), 'git_dir': s:GitDir(dir), 'flags': flags, 'curwin': curwin}
        if empty(args) && pager is# -1
            let cmd = s:StatusCommand(a:line1, a:line2, a:range, curwin ? 0 : a:line2, a:bang, a:mods, '', '', [], options)
            return (empty(cmd) ? 'exe' : cmd) . after
        en
        let alias = FugitiveConfigGet('alias.' . get(args, 0, ''), config)
        if get(args, 1, '') !=# '--help' && alias !~# '^$\|^!\|[\"'']' && !filereadable(FugitiveVimPath(s:ExecPath() . '/git-' . args[0]))
                    \ && !(has('win32') && filereadable(FugitiveVimPath(s:ExecPath() . '/git-' . args[0] . '.exe')))
            call remove(args, 0)
            call extend(args, split(alias, '\s\+'), 'keep')
        en
        let name = substitute(get(args, 0, ''), '\%(^\|-\)\(\l\)', '\u\1', 'g')
        if pager is# -1 && name =~# '^\a\+$' && exists('*s:' . name . 'Subcommand') && get(args, 1, '') !=# '--help'
            try
                let overrides = s:{name}Subcommand(a:line1, a:line2, a:range, a:bang, a:mods, extend({'subcommand': args[0], 'subcommand_args': args[1:-1]}, options))
                if type(overrides) == type('')
                    return 'exe ' . string(overrides) . after
                en
                let args = [get(overrides, 'command', args[0])] + get(overrides, 'insert_args', []) + args[1:-1]
            catch /^fugitive:/
                return 'echoerr ' . string(v:exception)
            endtry
        el
            let overrides = {}
        en
        call extend(env, get(overrides, 'env', {}))
        call s:PrepareEnv(env, dir)
        if pager is# -1
            let pager = fugitive#PagerFor(args, config)
        en
        let wants_terminal = type(pager) ==# type('') ||
                    \ (s:HasOpt(args, ['add', 'checkout', 'commit', 'reset', 'restore', 'stage', 'stash'], '-p', '--patch') ||
                    \ s:HasOpt(args, ['add', 'clean', 'stage'], '-i', '--interactive')) && pager is# 0
        if wants_terminal
            let mods = substitute(s:Mods(a:mods), '\<tab\>', '-tab', 'g')
            let assign = len(dir) ? '|let b:git_dir = ' . string(options.git_dir) : ''
            let argv = s:UserCommandList(options) + args
            let term_opts = len(env) ? {'env': env} : {}
            if has('nvim')
                call fugitive#Autowrite()
                return mods . (curwin ? 'enew' : 'new') . '|call termopen(' . string(argv) . ', ' . string(term_opts) . ')' . assign . '|startinsert' . after
            elseif exists('*term_start')
                call fugitive#Autowrite()
                if curwin
                    let term_opts.curwin = 1
                en
                return mods . 'call term_start(' . string(argv) . ', ' . string(term_opts) . ')' . assign . after
            en
        en
        let state = {
                    \ 'git': options.git,
                    \ 'flags': flags,
                    \ 'args': args,
                    \ 'dir': options.git_dir,
                    \ 'git_dir': options.git_dir,
                    \ 'cwd': s:UserCommandCwd(dir),
                    \ 'filetype': 'git',
                    \ 'mods': s:Mods(a:mods),
                    \ 'file': s:Resolve(tempname())}
        let allow_pty = 1
        let after_edit = ''
        let stream = 0
        if a:bang && pager isnot# 2
            let state.pager = pager
            let pager = 1
            let stream = exists('*setbufline')
            let do_edit = substitute(s:Mods(a:mods, 'Edge'), '\<tab\>', '-tab', 'g') . 'pedit!'
        elseif pager
            let allow_pty = 0
            if pager is# 2 && a:bang && a:line2 >= 0
                let [do_edit, after_edit] = s:ReadPrepare(a:line1, a:line2, a:range, a:mods)
            elseif pager is# 2 && a:bang
                let do_edit = s:Mods(a:mods) . 'pedit'
            elseif !curwin
                let do_edit = s:Mods(a:mods) . 'split'
            el
                let do_edit = s:Mods(a:mods) . 'edit'
                call s:BlurStatus()
            en
            call extend(env, {'COLUMNS': '' . get(g:, 'fugitive_columns', 80)}, 'keep')
        en
        if s:run_jobs
            call extend(env, {'COLUMNS': '' . (&columns - 1)}, 'keep')
            let state.pty = allow_pty && fugitive#CanPty()
            if !state.pty
                let args = s:AskPassArgs(dir) + args
            en
            let tmp = {
                        \ 'no_more': no_pager || get(overrides, 'no_more'),
                        \ 'line_count': 0,
                        \ 'err': '',
                        \ 'out': '',
                        \ 'escape': ''}
            let env.FUGITIVE = state.file
            let editor = 'sh ' . s:TempScript(
                        \ '[ -f "$FUGITIVE.exit" ] && cat "$FUGITIVE.exit" >&2 && exit 1',
                        \ 'echo "$1" > "$FUGITIVE.edit"',
                        \ 'printf "\033]51;fugitive:edit\007" >&2',
                        \ 'while [ -f "$FUGITIVE.edit" -a ! -f "$FUGITIVE.exit" ]; do sleep 0.05 2>/dev/null || sleep 1; done',
                        \ 'exit 0')
            call extend(env, {
                        \ 'NO_COLOR': '1',
                        \ 'GIT_EDITOR': editor,
                        \ 'GIT_SEQUENCE_EDITOR': editor,
                        \ 'GIT_PAGER': 'cat',
                        \ 'PAGER': 'cat'}, 'keep')
            if len($GPG_TTY) && !has_key(env, 'GPG_TTY')
                let env.GPG_TTY = ''
                let did_override_gpg_tty = 1
            en
            if stream
                call writefile(['fugitive: aborting edit due to background operation.'], state.file . '.exit')
            elseif pager
                call writefile(['fugitive: aborting edit due to use of pager.'], state.file . '.exit')
                let after = '|' . do_edit . ' ' . s:fnameescape(state.file) . after_edit . after
            el
                let env.GIT_MERGE_AUTOEDIT = '1'
                let tmp.echo = ''
            en
            let args = s:disable_colors + flags + ['-c', 'advice.waitingForEditor=false'] + args
            let argv = s:UserCommandList({'git': options.git, 'git_dir': options.git_dir}) + args
            let [argv, jobopts] = s:JobOpts(argv, env)
            call fugitive#Autowrite()
            call writefile([], state.file, 'b')
            call s:RunSave(state)
            if has_key(tmp, 'echo')
                echo ""
            en
            if exists('*ch_close_in')
                call extend(jobopts, {
                            \ 'mode': 'raw',
                            \ 'out_cb': function('s:RunReceive', [state, tmp, 'out']),
                            \ 'err_cb': function('s:RunReceive', [state, tmp, 'err']),
                            \ 'close_cb': function('s:RunClose', [state, tmp]),
                            \ 'exit_cb': function('s:RunExit', [state, tmp]),
                            \ })
                if state.pty
                    let jobopts.pty = 1
                en
                let job = job_start(argv, jobopts)
            el
                let job = jobstart(argv, extend(jobopts, {
                            \ 'pty': state.pty,
                            \ 'TERM': 'dumb',
                            \ 'on_stdout': function('s:RunReceive', [state, tmp, 'out']),
                            \ 'on_stderr': function('s:RunReceive', [state, tmp, 'err']),
                            \ 'on_exit': function('s:RunClose', [state, tmp]),
                            \ }))
            en
            let state.job = job
            if pager
                let tmp.closed_in = 1
                call s:RunCloseIn(job)
            en
            if stream
                exe 'silent' do_edit '++ff=unix' s:fnameescape(state.file)
                let state.capture_bufnr = bufnr(state.file)
                call setbufvar(state.capture_bufnr, '&modified', 1)
                return (after_edit . after)[1:-1]
            en
            call add(s:resume_queue, [state, tmp, job])
            return 'call fugitive#Resume()|checktime' . after
        elseif pager
            let pre = s:BuildEnvPrefix(env)
            try
                if exists('+guioptions') && &guioptions =~# '!'
                    let guioptions = &guioptions
                    set guioptions-=!
                en
                silent! execute '!' . escape(pre . s:shellesc(s:UserCommandList(options) + s:disable_colors + flags + ['--no-pager'] + args), '!#%') .
                            \ (&shell =~# 'csh' ? ' >& ' . s:shellesc(state.file) : ' > ' . s:shellesc(state.file) . ' 2>&1')
                let state.exit_status = v:shell_error
            finally
                if exists('guioptions')
                    let &guioptions = guioptions
                en
            endtry
            redraw!
            call s:RunSave(state)
            call s:RunFinished(state)
            return do_edit . ' ' . s:fnameescape(state.file) . after_edit .
                        \ '|call fugitive#DidChange(fugitive#Result(' . string(state.file) . '))' . after
        elseif has('win32')
            return 'echoerr ' . string('fugitive: Vim 8 with job support required to use :Git on Windows')
        elseif has('gui_running')
            return 'echoerr ' . string('fugitive: Vim 8 with job support required to use :Git in GVim')
        el
            if !explicit_pathspec_option && get(options.flags, 0, '') ==# '--no-literal-pathspecs'
                call remove(options.flags, 0)
            en
            if exists('l:did_override_gpg_tty')
                call remove(env, 'GPG_TTY')
            en
            let cmd = s:BuildEnvPrefix(env) . s:shellesc(s:UserCommandList(options) + args)
            let after = '|call fugitive#DidChange(' . string(dir) . ')' . after
            if !wants_terminal && (no_pager || index(['add', 'clean', 'reset', 'restore', 'stage'], get(args, 0, '')) >= 0 || s:HasOpt(args, ['checkout'], '-q', '--quiet', '--no-progress'))
                let output = substitute(s:SystemError(cmd)[0], "\n$", '', '')
                if len(output)
                    try
                        if &more && no_pager
                            let more = 1
                            set nomore
                        en
                        echo substitute(output, "\n$", "", "")
                    finally
                        if exists('l:more')
                            set more
                        en
                    endtry
                en
                return 'checktime' . after
            el
                return 'exe ' . string('noautocmd !' . escape(cmd, '!#%')) . after
            en
        en
    endf

    let s:exec_paths = {}
    fun! s:ExecPath() abort
        let git = s:GitShellCmd()
        if !has_key(s:exec_paths, git)
            let s:exec_paths[git] = get(s:JobExecute(s:GitCmd() + ['--exec-path'], {}, [], [], {}).stdout, 0, '')
        en
        return s:exec_paths[git]
    endf

    let s:subcommands_before_2_5 = [
                \ 'add', 'am', 'apply', 'archive', 'bisect', 'blame', 'branch', 'bundle',
                \ 'checkout', 'cherry', 'cherry-pick', 'citool', 'clean', 'clone', 'commit', 'config',
                \ 'describe', 'diff', 'difftool', 'fetch', 'format-patch', 'fsck',
                \ 'gc', 'grep', 'gui', 'help', 'init', 'instaweb', 'log',
                \ 'merge', 'mergetool', 'mv', 'notes', 'pull', 'push',
                \ 'rebase', 'reflog', 'remote', 'repack', 'replace', 'request-pull', 'reset', 'revert', 'rm',
                \ 'send-email', 'shortlog', 'show', 'show-branch', 'stash', 'stage', 'status', 'submodule',
                \ 'tag', 'whatchanged',
                \ ]
    let s:path_subcommands = {}
    fun! s:CompletableSubcommands(dir) abort
        let c_exec_path = s:cpath(s:ExecPath())
        if !has_key(s:path_subcommands, c_exec_path)
            if fugitive#GitVersion(2, 18)
                let [lines, exec_error] = s:LinesError([a:dir, '--list-cmds=list-mainporcelain,nohelpers,list-complete'])
                call filter(lines, 'v:val =~# "^\\S\\+$"')
                if !exec_error && len(lines)
                    let s:path_subcommands[c_exec_path] = lines
                el
                    let s:path_subcommands[c_exec_path] = s:subcommands_before_2_5 +
                                \ ['maintenance', 'prune', 'range-diff', 'restore', 'sparse-checkout', 'switch', 'worktree']
                en
            el
                let s:path_subcommands[c_exec_path] = s:subcommands_before_2_5 +
                            \ (fugitive#GitVersion(2, 5) ? ['worktree'] : [])
            en
        en
        let commands = copy(s:path_subcommands[c_exec_path])
        for path in split($PATH, has('win32') ? ';' : ':')
            if path !~# '^/\|^\a:[\\/]'
                continue
            en
            let cpath = s:cpath(path)
            if !has_key(s:path_subcommands, cpath)
                let s:path_subcommands[cpath] = filter(map(s:GlobComplete(path.'/git-', '*', 1),'substitute(v:val,"\\.exe$","","")'), 'v:val !~# "--\\|/"')
            en
            call extend(commands, s:path_subcommands[cpath])
        endfor
        call extend(commands, keys(fugitive#ConfigGetRegexp('^alias\.\zs[^.]\+$', a:dir)))
        let configured = split(FugitiveConfigGet('completion.commands', a:dir), '\s\+')
        let rejected = {}
        for command in configured
            if command =~# '^-.'
                let rejected[strpart(command, 1)] = 1
            en
        endfor
        call filter(configured, 'v:val !~# "^-"')
        let results = filter(sort(commands + configured), '!has_key(rejected, v:val)')
        if exists('*uniq')
            return uniq(results)
        el
            let i = 1
            while i < len(results)
                if results[i] ==# results[i-1]
                    call remove(results, i)
                el
                    let i += 1
                en
            endwhile
            return results
        en
    endf

    fun! fugitive#Complete(lead, ...) abort
        let dir = a:0 == 1 ? a:1 : a:0 >= 3 ? s:Dir(a:3) : s:Dir()
        let root = a:0 >= 4 ? a:4 : s:Tree(s:Dir())
        let pre = a:0 > 1 ? strpart(a:1, 0, a:2) : ''
        let subcmd = matchstr(pre, '\u\w*[! ] *\%(\%(++\S\+\|--\S\+-pathspecs\|-c\s\+\S\+\)\s\+\)*\zs[[:alnum:]][[:alnum:]-]*\ze ')
        if empty(subcmd) && a:lead =~# '^+'
            let results = ['++curwin']
        elseif empty(subcmd) && a:lead =~# '^-'
            let results = ['--literal-pathspecs', '--no-literal-pathspecs', '--glob-pathspecs', '--noglob-pathspecs', '--icase-pathspecs', '--no-optional-locks']
        elseif empty(subcmd)
            let results = s:CompletableSubcommands(dir)
        elseif a:0 ==# 2 && subcmd =~# '^\%(commit\|revert\|push\|fetch\|pull\|merge\|rebase\|bisect\)$'
            let cmdline = substitute(a:1, '\u\w*\([! ] *\)' . subcmd, 'G' . subcmd, '')
            let caps_subcmd = substitute(subcmd, '\%(^\|-\)\l', '\u&', 'g')
            return fugitive#{caps_subcmd}Complete(a:lead, cmdline, a:2 + len(cmdline) - len(a:1), dir, root)
        elseif pre =~# ' -- '
            return fugitive#CompletePath(a:lead, a:1, a:2, dir, root)
        elseif a:lead =~# '^-'
            let results = split(s:ChompDefault('', [dir, subcmd, '--git-completion-helper']), ' ')
        el
            return fugitive#CompleteObject(a:lead, a:1, a:2, dir, root)
        en
        return filter(results, 'strpart(v:val, 0, strlen(a:lead)) ==# a:lead')
    endf

    fun! fugitive#CompleteForWorkingDir(A, L, P, ...) abort
        let path = a:0 ? a:1 : getcwd()
        return fugitive#Complete(a:A, a:L, a:P, FugitiveExtractGitDir(path), path)
    endf

" Section: :Gcd, :Glcd

    fun! fugitive#CdComplete(A, L, P) abort
        return filter(fugitive#CompletePath(a:A), 'v:val =~# "/$"')
    endf

    fun! fugitive#Cd(path, ...) abort
        let path = substitute(a:path, '^:/:\=\|^:(\%(top\|top,literal\|literal,top\|literal\))', '', '')
        if path !~# '^/\|^\a\+:\|^\.\.\=\%(/\|$\)'
            let dir = s:Dir()
            exe s:DirCheck(dir)
            let path = (empty(s:Tree(dir)) ? dir : s:Tree(dir)) . '/' . path
        en
        return (a:0 && a:1 ? 'lcd ' : 'cd ') . s:fnameescape(FugitiveVimPath(path))
    endf

" Section: :Gstatus
    fun! s:StatusCommand(line1, line2, range, count, bang, mods, reg, arg, args, ...) abort
        let dir = a:0 ? s:Dir(a:1) : s:Dir()
        exe s:DirCheck(dir)
        try
            let mods = s:Mods(a:mods, 'Edge')
            let file = fugitive#Find(':', dir)
            let arg = ' +setl\ foldmarker=<<<<<<<<,>>>>>>>>\|let\ w:fugitive_status=FugitiveGitDir() ' .
                        \ s:fnameescape(file)
            for tabnr in [tabpagenr()] + (mods =~# '\<tab\>' ? range(1, tabpagenr('$')) : [])
                let bufs = tabpagebuflist(tabnr)
                for winnr in range(1, tabpagewinnr(tabnr, '$'))
                    if s:cpath(file, fnamemodify(bufname(bufs[winnr-1]), ':p'))
                        if tabnr == tabpagenr() && winnr == winnr()
                            call s:ReloadStatus()
                        el
                            call s:ExpireStatus(dir)
                            exe tabnr . 'tabnext'
                            exe winnr . 'wincmd w'
                        en
                        let w:fugitive_status = dir
                        1
                        return ''
                    en
                endfor
            endfor
            if a:count ==# 0
                return mods . 'edit' . (a:bang ? '!' : '') . arg
            elseif a:bang
                return mods . 'pedit' . arg . '|wincmd P'
            el
                return mods . 'keepalt split' . arg
            en
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        return ''
    endf

    fun! s:StageJump(offset, section, ...) abort
        let line = search('^\%(' . a:section . '\)', 'nw')
        if !line && a:0
            let line = search('^\%(' . a:1 . '\)', 'nw')
        en
        if line
            exe line
            if a:offset
                for i in range(a:offset)
                    call search(s:file_commit_pattern . '\|^$', 'W')
                    if empty(getline('.')) && a:0 && getline(line('.') + 1) =~# '^\%(' . a:1 . '\)'
                        call search(s:file_commit_pattern . '\|^$', 'W')
                    en
                    if empty(getline('.'))
                        return ''
                    en
                endfor
                call s:StageReveal()
            el
                call s:StageReveal()
                +
            en
        en
        return ''
    endf

    fun! s:StageSeek(info, fallback) abort
        let info = a:info
        if empty(info.heading)
            return a:fallback
        en
        let line = search('^' . escape(info.heading, '^$.*[]~\') . ' (\d\++\=)$', 'wn')
        if !line
            for section in get({'Staged': ['Unstaged', 'Untracked'], 'Unstaged': ['Untracked', 'Staged'], 'Untracked': ['Unstaged', 'Staged']}, info.section, [])
                let line = search('^' . section, 'wn')
                if line
                    return line + (info.index > 0 ? 1 : 0)
                en
            endfor
            return 1
        en
        let i = 0
        while len(getline(line))
            let filename = matchstr(getline(line), '^[A-Z?] \zs.*')
            if len(filename) &&
                        \ ((info.filename[-1:-1] ==# '/' && filename[0 : len(info.filename) - 1] ==# info.filename) ||
                        \ (filename[-1:-1] ==# '/' && filename ==# info.filename[0 : len(filename) - 1]) ||
                        \ filename ==# info.filename)
                if info.offset < 0
                    return line
                el
                    if getline(line+1) !~# '^@'
                        exe s:StageInline('show', line)
                    en
                    if getline(line+1) !~# '^@'
                        return line
                    en
                    let type = info.sigil ==# '-' ? '-' : '+'
                    let offset = -1
                    while offset < info.offset
                        let line += 1
                        if getline(line) =~# '^@'
                            let offset = +matchstr(getline(line), type . '\zs\d\+') - 1
                        elseif getline(line) =~# '^[ ' . type . ']'
                            let offset += 1
                        elseif getline(line) !~# '^[ @\+-]'
                            return line - 1
                        en
                    endwhile
                    return line
                en
            en
            let commit = matchstr(getline(line), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\+')
            if len(commit) && commit ==# info.commit
                return line
            en
            if i ==# info.index
                let backup = line
            en
            let i += getline(line) !~# '^[ @\+-]'
            let line += 1
        endwhile
        return exists('backup') ? backup : line - 1
    endf

    fun! s:DoAutocmdChanged(dir) abort
        let dir = a:dir is# -2 ? '' : FugitiveGitDir(a:dir)
        if empty(dir) || !exists('#User#FugitiveChanged') || exists('g:fugitive_event')
            return ''
        en
        try
            let g:fugitive_event = dir
            if type(a:dir) == type({}) && has_key(a:dir, 'args') && has_key(a:dir, 'exit_status')
                let g:fugitive_result = a:dir
            en
            exe s:DoAutocmd('User FugitiveChanged')
        finally
            unlet! g:fugitive_event g:fugitive_result
            " Force statusline reload with the buffer's Git dir
            let &l:ro = &l:ro
        endtry
        return ''
    endf

    fun! s:ReloadStatusBuffer(...) abort
        if get(b:, 'fugitive_type', '') !=# 'index'
            return ''
        en
        let original_lnum = a:0 ? a:1 : line('.')
        let info = s:StageInfo(original_lnum)
        call fugitive#BufReadStatus(0)
        call setpos('.', [0, s:StageSeek(info, original_lnum), 1, 0])
        return ''
    endf

    fun! s:ReloadStatus(...) abort
        call s:ExpireStatus(-1)
        call s:ReloadStatusBuffer(a:0 ? a:1 : line('.'))
        exe s:DoAutocmdChanged(-1)
        return ''
    endf

    let s:last_time = reltime()
    if !exists('s:last_times')
        let s:last_times = {}
    en

    fun! s:ExpireStatus(bufnr) abort
        if a:bufnr is# -2 || a:bufnr is# 0
            let s:head_cache = {}
            let s:last_time = reltime()
            return ''
        en
        let dir = s:Dir(a:bufnr)
        if len(dir)
            let s:last_times[s:cpath(dir)] = reltime()
            if has_key(s:head_cache, dir)
                call remove(s:head_cache, dir)
            en
        en
        return ''
    endf

    fun! s:ReloadWinStatus(...) abort
        if get(b:, 'fugitive_type', '') !=# 'index' || &modified
            return
        en
        if !exists('b:fugitive_reltime')
            exe s:ReloadStatusBuffer()
            return
        en
        let t = b:fugitive_reltime
        if reltimestr(reltime(s:last_time, t)) =~# '-\|\d\{10\}\.' ||
                    \ reltimestr(reltime(get(s:last_times, s:cpath(s:Dir()), t), t)) =~# '-\|\d\{10\}\.'
            exe s:ReloadStatusBuffer()
        en
    endf

    fun! s:ReloadTabStatus(...) abort
        let mytab = tabpagenr()
        let tab = a:0 ? a:1 : mytab
        let winnr = 1
        while winnr <= tabpagewinnr(tab, '$')
            if getbufvar(tabpagebuflist(tab)[winnr-1], 'fugitive_type') ==# 'index'
                exe  'tabnext '.tab
                if winnr != winnr()
                    exe  winnr.'wincmd w'
                    let restorewinnr = 1
                en
                try
                    call s:ReloadWinStatus()
                finally
                    if exists('restorewinnr')
                        unlet restorewinnr
                        wincmd p
                    en
                    exe  'tabnext '.mytab
                endtry
            en
            let winnr += 1
        endwhile
        unlet! t:fugitive_reload_status
    endf

    fun! fugitive#DidChange(...) abort
        call s:ExpireStatus(a:0 ? a:1 : -1)
        if a:0 > 1 ? a:2 : (!a:0 || a:1 isnot# 0)
            let t = reltime()
            let t:fugitive_reload_status = t
            for tabnr in exists('*settabvar') ? range(1, tabpagenr('$')) : []
                call settabvar(tabnr, 'fugitive_reload_status', t)
            endfor
            call s:ReloadTabStatus()
        el
            call s:ReloadWinStatus()
            return ''
        en
        exe s:DoAutocmdChanged(a:0 ? a:1 : -1)
        return ''
    endf

    fun! fugitive#ReloadStatus(...) abort
        return call('fugitive#DidChange', a:000)
    endf

    fun! fugitive#EfmDir(...) abort
        let dir = matchstr(a:0 ? a:1 : &errorformat, '\c,%\\&\%(git\|fugitive\)_\=dir=\zs\%(\\.\|[^,]\)*')
        let dir = substitute(dir, '%%', '%', 'g')
        let dir = substitute(dir, '\\\ze[\,]', '', 'g')
        return dir
    endf

    aug  fugitive_status
        au!
        au BufWritePost         * call fugitive#DidChange(+expand('<abuf>'), 0)
        au User FileChmodPost,FileUnlinkPost call fugitive#DidChange(+expand('<abuf>'), 0)
        au ShellCmdPost,ShellFilterPost * nested call fugitive#DidChange(0)
        au BufDelete * nested
                    \ if getbufvar(+expand('<abuf>'), 'buftype') ==# 'terminal' |
                    \   if !empty(FugitiveGitDir(+expand('<abuf>'))) |
                    \     call fugitive#DidChange(+expand('<abuf>')) |
                    \   else |
                    \     call fugitive#DidChange(0) |
                    \  endif |
                    \ endif
        au QuickFixCmdPost make,lmake,[cl]file,[cl]getfile nested
                    \ call fugitive#DidChange(fugitive#EfmDir())
        au FocusGained        *
                    \ if get(g:, 'fugitive_focus_gained', !has('win32')) |
                    \   call fugitive#DidChange(0) |
                    \ endif
        au BufEnter index,index.lock
                    \ call s:ReloadWinStatus()
        au TabEnter *
                    \ if exists('t:fugitive_reload_status') |
                    \    call s:ReloadTabStatus() |
                    \ endif
    aug  END

    fun! s:StageInfo(...) abort
        let lnum = a:0 ? a:1 : line('.')
        let sigil = matchstr(getline(lnum), '^[ @\+-]')
        let offset = -1
        if len(sigil)
            let type = sigil ==# '-' ? '-' : '+'
            while lnum > 0 && getline(lnum) !~# '^@'
                if getline(lnum) =~# '^[ '.type.']'
                    let offset += 1
                en
                let lnum -= 1
            endwhile
            let offset += matchstr(getline(lnum), type.'\zs\d\+')
            while getline(lnum) =~# '^[ @\+-]'
                let lnum -= 1
            endwhile
        en
        let slnum = lnum + 1
        let heading = ''
        let index = 0
        while len(getline(slnum - 1)) && empty(heading)
            let slnum -= 1
            let heading = matchstr(getline(slnum), '^\u\l\+.\{-\}\ze (\d\++\=)$')
            if empty(heading) && getline(slnum) !~# '^[ @\+-]'
                let index += 1
            en
        endwhile
        let text = matchstr(getline(lnum), '^[A-Z?] \zs.*')
        let file = get(get(b:fugitive_files, heading, {}), text, {})
        let relative = get(file, 'relative', len(text) ? [text] : [])
        return {'section': matchstr(heading, '^\u\l\+'),
                    \ 'heading': heading,
                    \ 'sigil': sigil,
                    \ 'offset': offset,
                    \ 'filename': text,
                    \ 'relative': copy(relative),
                    \ 'paths': map(copy(relative), 's:Tree() . "/" . v:val'),
                    \ 'commit': matchstr(getline(lnum), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\{4,\}\ze '),
                    \ 'status': matchstr(getline(lnum), '^[A-Z?]\ze \|^\%(\x\x\x\)\@!\l\+\ze [0-9a-f]'),
                    \ 'submodule': get(file, 'submodule', ''),
                    \ 'index': index}
    endf

    fun! s:Selection(arg1, ...) abort
        if a:arg1 ==# 'n'
            let arg1 = line('.')
            let arg2 = -v:count
        elseif a:arg1 ==# 'v'
            let arg1 = line("'<")
            let arg2 = line("'>")
        el
            let arg1 = a:arg1
            let arg2 = a:0 ? a:1 : 0
        en
        let first = arg1
        if arg2 < 0
            let last = first - arg2 - 1
        elseif arg2 > 0
            let last = arg2
        el
            let last = first
        en
        while first <= line('$') && getline(first) =~# '^$\|^[A-Z][a-z]'
            let first += 1
        endwhile
        if first > last || &filetype !=# 'fugitive'
            return []
        en
        let flnum = first
        while getline(flnum) =~# '^[ @\+-]'
            let flnum -= 1
        endwhile
        let slnum = flnum + 1
        let heading = ''
        let index = 0
        while empty(heading)
            let slnum -= 1
            let heading = matchstr(getline(slnum), '^\u\l\+.\{-\}\ze (\d\++\=)$')
            if empty(heading) && getline(slnum) !~# '^[ @\+-]'
                let index += 1
            en
        endwhile
        let results = []
        let template = {
                    \ 'heading': heading,
                    \ 'section': matchstr(heading, '^\u\l\+'),
                    \ 'filename': '',
                    \ 'relative': [],
                    \ 'paths': [],
                    \ 'commit': '',
                    \ 'status': '',
                    \ 'patch': 0,
                    \ 'index': index}
        let line = getline(flnum)
        let lnum = first - (arg1 == flnum ? 0 : 1)
        let root = s:Tree() . '/'
        while lnum <= last
            let heading = matchstr(line, '^\u\l\+\ze.\{-\}\ze (\d\++\=)$')
            if len(heading)
                let template.heading = heading
                let template.section = matchstr(heading, '^\u\l\+')
                let template.index = 0
            elseif line =~# '^[ @\+-]'
                let template.index -= 1
                if !results[-1].patch
                    let results[-1].patch = lnum
                en
                let results[-1].lnum = lnum
            elseif line =~# '^[A-Z?] '
                let text = matchstr(line, '^[A-Z?] \zs.*')
                let file = get(get(b:fugitive_files, template.heading, {}), text, {})
                let relative = get(file, 'relative', len(text) ? [text] : [])
                call add(results, extend(deepcopy(template), {
                            \ 'lnum': lnum,
                            \ 'filename': text,
                            \ 'relative': copy(relative),
                            \ 'paths': map(copy(relative), 'root . v:val'),
                            \ 'status': matchstr(line, '^[A-Z?]'),
                            \ }))
            elseif line =~# '^\x\x\x\+ '
                call add(results, extend({
                            \ 'lnum': lnum,
                            \ 'commit': matchstr(line, '^\x\x\x\+'),
                            \ }, template, 'keep'))
            elseif line =~# '^\l\+ \x\x\x\+ '
                call add(results, extend({
                            \ 'lnum': lnum,
                            \ 'commit': matchstr(line, '^\l\+ \zs\x\x\x\+'),
                            \ 'status': matchstr(line, '^\l\+'),
                            \ }, template, 'keep'))
            en
            let lnum += 1
            let template.index += 1
            let line = getline(lnum)
        endwhile
        if len(results) && results[0].patch && arg2 == 0
            while getline(results[0].patch) =~# '^[ \+-]'
                let results[0].patch -= 1
            endwhile
            while getline(results[0].lnum + 1) =~# '^[ \+-]'
                let results[0].lnum += 1
            endwhile
        en
        return results
    endf

    fun! s:StageArgs(visual) abort
        let commits = []
        let paths = []
        for record in s:Selection(a:visual ? 'v' : 'n')
            if len(record.commit)
                call add(commits, record.commit)
            en
            call extend(paths, record.paths)
        endfor
        if s:cpath(s:Tree(), getcwd())
            call map(paths, 'fugitive#Path(v:val, "./")')
        en
        return join(map(commits + paths, 's:fnameescape(v:val)'), ' ')
    endf

    fun! s:Do(action, visual) abort
        let line = getline('.')
        let reload = 0
        if !a:visual && !v:count && line =~# '^[A-Z][a-z]'
            let header = matchstr(line, '^\S\+\ze:')
            if len(header) && exists('*s:Do' . a:action . header . 'Header')
                let reload = s:Do{a:action}{header}Header(matchstr(line, ': \zs.*')) > 0
            el
                let section = matchstr(line, '^\S\+')
                if exists('*s:Do' . a:action . section . 'Heading')
                    let reload = s:Do{a:action}{section}Heading(line) > 0
                en
            en
            return reload ? s:ReloadStatus() : ''
        en
        let selection = s:Selection(a:visual ? 'v' : 'n')
        if empty(selection)
            return ''
        en
        call filter(selection, 'v:val.section ==# selection[0].section')
        let status = 0
        let err = ''
        try
            for record in selection
                if exists('*s:Do' . a:action . record.section)
                    let status = s:Do{a:action}{record.section}(record)
                el
                    continue
                en
                if !status
                    return ''
                en
                let reload = reload || (status > 0)
            endfor
            if status < 0
                exe  record.lnum + 1
            en
            let success = 1
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        finally
            if reload
                exe  s:ReloadStatus()
            en
            if exists('success')
                call s:StageReveal()
            en
        endtry
        return ''
    endf

    fun! s:StageReveal() abort
        exe 'normal! zv'
        let begin = line('.')
        if getline(begin) =~# '^@'
            let end = begin + 1
            while getline(end) =~# '^[ \+-]'
                let end += 1
            endwhile
        elseif getline(begin) =~# '^commit '
            let end = begin
            while end < line('$') && getline(end + 1) !~# '^commit '
                let end += 1
            endwhile
        elseif getline(begin) =~# s:section_pattern
            let end = begin
            while len(getline(end + 1))
                let end += 1
            endwhile
        en
        if exists('end')
            while line('.') > line('w0') + &scrolloff && end > line('w$')
                exe  "normal! \<C-E>"
            endwhile
        en
    endf

    let s:file_pattern = '^[A-Z?] .\|^diff --'
    let s:file_commit_pattern = s:file_pattern . '\|^\%(\l\{3,\} \)\=[0-9a-f]\{4,\} '
    let s:item_pattern = s:file_commit_pattern . '\|^@@'

    fun! s:NextHunk(count) abort
        if &filetype ==# 'fugitive' && getline('.') =~# s:file_pattern
            exe s:StageInline('show')
        en
        for i in range(a:count)
            if &filetype ==# 'fugitive'
                call search(s:file_pattern . '\|^@', 'W')
                if getline('.') =~# s:file_pattern
                    exe s:StageInline('show')
                    if getline(line('.') + 1) =~# '^@'
                        +
                    en
                en
            el
                call search('^@@', 'W')
            en
        endfor
        call s:StageReveal()
        return '.'
    endf

    fun! s:PreviousHunk(count) abort
        for i in range(a:count)
            if &filetype ==# 'fugitive'
                let lnum = search(s:file_pattern . '\|^@','Wbn')
                call s:StageInline('show', lnum)
                call search('^? .\|^@','Wb')
            el
                call search('^@@', 'Wb')
            en
        endfor
        call s:StageReveal()
        return '.'
    endf

    fun! s:NextFile(count) abort
        for i in range(a:count)
            exe s:StageInline('hide')
            if !search(s:file_pattern, 'W')
                break
            en
        endfor
        exe s:StageInline('hide')
        return '.'
    endf

    fun! s:PreviousFile(count) abort
        exe s:StageInline('hide')
        for i in range(a:count)
            if !search(s:file_pattern, 'Wb')
                break
            en
            exe s:StageInline('hide')
        endfor
        return '.'
    endf

    fun! s:NextItem(count) abort
        for i in range(a:count)
            if !search(s:item_pattern, 'W') && getline('.') !~# s:item_pattern
                call search('^commit ', 'W')
            en
        endfor
        call s:StageReveal()
        return '.'
    endf

    fun! s:PreviousItem(count) abort
        for i in range(a:count)
            if !search(s:item_pattern, 'Wb') && getline('.') !~# s:item_pattern
                call search('^commit ', 'Wb')
            en
        endfor
        call s:StageReveal()
        return '.'
    endf

    let s:section_pattern = '^[A-Z][a-z][^:]*$'
    let s:section_commit_pattern = s:section_pattern . '\|^commit '

    fun! s:NextSection(count) abort
        let orig = line('.')
        if getline('.') !~# '^commit '
            -
        en
        for i in range(a:count)
            if !search(s:section_commit_pattern, 'W')
                break
            en
        endfor
        if getline('.') =~# s:section_commit_pattern
            call s:StageReveal()
            return getline('.') =~# s:section_pattern ? '+' : ':'
        el
            return orig
        en
    endf

    fun! s:PreviousSection(count) abort
        let orig = line('.')
        if getline('.') !~# '^commit '
            -
        en
        for i in range(a:count)
            if !search(s:section_commit_pattern . '\|\%^', 'bW')
                break
            en
        endfor
        if getline('.') =~# s:section_commit_pattern || line('.') == 1
            call s:StageReveal()
            return getline('.') =~# s:section_pattern ? '+' : ':'
        el
            return orig
        en
    endf

    fun! s:NextSectionEnd(count) abort
        +
        if empty(getline('.'))
            +
        en
        for i in range(a:count)
            if !search(s:section_commit_pattern, 'W')
                return '$'
            en
        endfor
        return search('^.', 'Wb')
    endf

    fun! s:PreviousSectionEnd(count) abort
        let old = line('.')
        for i in range(a:count)
            if search(s:section_commit_pattern, 'Wb') <= 1
                exe old
                if i
                    break
                el
                    return ''
                en
            en
            let old = line('.')
        endfor
        return search('^.', 'Wb')
    endf

    fun! s:PatchSearchExpr(reverse) abort
        let line = getline('.')
        if col('.') ==# 1 && line =~# '^[+-]'
            if line =~# '^[+-]\{3\} '
                let pattern = '^[+-]\{3\} ' . substitute(escape(strpart(line, 4), '^$.*[]~\'), '^\w/', '\\w/', '') . '$'
            el
                let pattern = '^[+-]\s*' . escape(substitute(strpart(line, 1), '^\s*\|\s*$', '', ''), '^$.*[]~\') . '\s*$'
            en
            if a:reverse
                return '?' . escape(pattern, '/?') . "\<CR>"
            el
                return '/' . escape(pattern, '/') . "\<CR>"
            en
        en
        return a:reverse ? '#' : '*'
    endf

    fun! s:StageInline(mode, ...) abort
        if &filetype !=# 'fugitive'
            return ''
        en
        let lnum1 = a:0 ? a:1 : line('.')
        let lnum = lnum1 + 1
        if a:0 > 1 && a:2 == 0 && lnum1 == 1
            let lnum = line('$') - 1
        elseif a:0 > 1 && a:2 == 0
            let info = s:StageInfo(lnum - 1)
            if empty(info.paths) && len(info.section)
                while len(getline(lnum))
                    let lnum += 1
                endwhile
            en
        elseif a:0 > 1
            let lnum += a:2 - 1
        en
        while lnum > lnum1
            let lnum -= 1
            while lnum > 0 && getline(lnum) =~# '^[ @\+-]'
                let lnum -= 1
            endwhile
            let info = s:StageInfo(lnum)
            if !has_key(b:fugitive_diff, info.section)
                continue
            en
            if getline(lnum + 1) =~# '^[ @\+-]'
                let lnum2 = lnum + 1
                while getline(lnum2 + 1) =~# '^[ @\+-]'
                    let lnum2 += 1
                endwhile
                if a:mode !=# 'show'
                    setl  modifiable noreadonly
                    exe 'silent keepjumps ' . (lnum + 1) . ',' . lnum2 . 'delete _'
                    call remove(b:fugitive_expanded[info.section], info.filename)
                    setl  nomodifiable readonly nomodified
                en
                continue
            en
            if !has_key(b:fugitive_diff, info.section) || info.status !~# '^[ADMRU]$' || a:mode ==# 'hide'
                continue
            en
            let mode = ''
            let diff = []
            let index = 0
            let start = -1
            for line in fugitive#Wait(b:fugitive_diff[info.section]).stdout
                if mode ==# 'await' && line[0] ==# '@'
                    let mode = 'capture'
                en
                if mode !=# 'head' && line !~# '^[ @\+-]'
                    if len(diff)
                        break
                    en
                    let start = index
                    let mode = 'head'
                elseif mode ==# 'head' && line =~# '^diff '
                    let start = index
                elseif mode ==# 'head' && substitute(line, "\t$", '', '') ==# '--- ' . info.relative[-1]
                    let mode = 'await'
                elseif mode ==# 'head' && substitute(line, "\t$", '', '') ==# '+++ ' . info.relative[0]
                    let mode = 'await'
                elseif mode ==# 'capture'
                    call add(diff, line)
                elseif line[0] ==# '@'
                    let mode = ''
                en
                let index += 1
            endfor
            if len(diff)
                setl  modifiable noreadonly
                silent call append(lnum, diff)
                let b:fugitive_expanded[info.section][info.filename] = [start, len(diff)]
                setl  nomodifiable readonly nomodified
                if foldclosed(lnum+1) > 0
                    silent exe (lnum+1) . ',' . (lnum+len(diff)) . 'foldopen!'
                en
            en
        endwhile
        return lnum
    endf

    fun! s:NextExpandedHunk(count) abort
        for i in range(a:count)
            call s:StageInline('show', line('.'), 1)
            call search(s:file_pattern . '\|^@','W')
        endfor
        return '.'
    endf

    fun! s:StageDiff(diff) abort
        let lnum = line('.')
        let info = s:StageInfo(lnum)
        let prefix = info.offset > 0 ? '+' . info.offset : ''
        if info.submodule =~# '^S'
            if info.section ==# 'Staged'
                return 'Git --paginate diff --no-ext-diff --submodule=log --cached -- ' . info.paths[0]
            elseif info.submodule =~# '^SC'
                return 'Git --paginate diff --no-ext-diff --submodule=log -- ' . info.paths[0]
            el
                return 'Git --paginate diff --no-ext-diff --submodule=diff -- ' . info.paths[0]
            en
        elseif empty(info.paths) && info.section ==# 'Staged'
            return 'Git --paginate diff --no-ext-diff --cached'
        elseif empty(info.paths)
            return 'Git --paginate diff --no-ext-diff'
        elseif len(info.paths) > 1
            exe  'Gedit' . prefix s:fnameescape(':0:' . info.paths[0])
            return a:diff . '! @:'.s:fnameescape(info.paths[1])
        elseif info.section ==# 'Staged' && info.sigil ==# '-'
            exe  'Gedit' prefix s:fnameescape(':0:'.info.paths[0])
            return a:diff . '! :0:%'
        elseif info.section ==# 'Staged'
            exe  'Gedit' prefix s:fnameescape(':0:'.info.paths[0])
            return a:diff . '! @:%'
        elseif info.sigil ==# '-'
            exe  'Gedit' prefix s:fnameescape(':0:'.info.paths[0])
            return a:diff . '! :(top)%'
        el
            exe  'Gedit' prefix s:fnameescape(':(top)'.info.paths[0])
            return a:diff . '!'
        en
    endf

    fun! s:StageDiffEdit() abort
        let info = s:StageInfo(line('.'))
        let arg = (empty(info.paths) ? s:Tree() : info.paths[0])
        if info.section ==# 'Staged'
            return 'Git --paginate diff --no-ext-diff --cached '.s:fnameescape(arg)
        elseif info.status ==# '?'
            call s:TreeChomp('add', '--intent-to-add', '--', arg)
            return s:ReloadStatus()
        el
            return 'Git --paginate diff --no-ext-diff '.s:fnameescape(arg)
        en
    endf

    fun! s:StageApply(info, reverse, extra) abort
        if a:info.status ==# 'R'
            throw 'fugitive: patching renamed file not yet supported'
        en
        let cmd = ['apply', '-p0', '--recount'] + a:extra
        let info = a:info
        let start = info.patch
        let end = info.lnum
        let lines = getline(start, end)
        if empty(filter(copy(lines), 'v:val =~# "^[+-]"'))
            return -1
        en
        while getline(end) =~# '^[-+\ ]'
            let end += 1
            if getline(end) =~# '^[' . (a:reverse ? '+' : '-') . '\ ]'
                call add(lines, ' ' . getline(end)[1:-1])
            en
        endwhile
        while start > 0 && getline(start) !~# '^@'
            let start -= 1
            if getline(start) =~# '^[' . (a:reverse ? '+' : '-') . ' ]'
                call insert(lines, ' ' . getline(start)[1:-1])
            elseif getline(start) =~# '^@'
                call insert(lines, getline(start))
            en
        endwhile
        if start == 0
            throw 'fugitive: could not find hunk'
        elseif getline(start) !~# '^@@ '
            throw 'fugitive: cannot apply conflict hunk'
        en
        let i = b:fugitive_expanded[info.section][info.filename][0]
        let head = []
        let diff_lines = fugitive#Wait(b:fugitive_diff[info.section]).stdout
        while get(diff_lines, i, '@') !~# '^@'
            let line = diff_lines[i]
            if line ==# '--- /dev/null'
                call add(head, '--- ' . get(diff_lines, i + 1, '')[4:-1])
            elseif line !~# '^new file '
                call add(head, line)
            en
            let i += 1
        endwhile
        call extend(lines, head, 'keep')
        let temp = tempname()
        call writefile(lines, temp)
        if a:reverse
            call add(cmd, '--reverse')
        en
        call extend(cmd, ['--', temp])
        let output = s:ChompStderr(cmd)
        if empty(output)
            return 1
        en
        call s:throw(output)
    endf

    fun! s:StageDelete(lnum1, lnum2, count) abort
        let restore = []

        let err = ''
        let did_conflict_err = 0
        let reset_commit = matchstr(getline(a:lnum1), '^Un\w\+ \%(to\| from\) \zs\S\+')
        try
            for info in s:Selection(a:lnum1, a:lnum2)
                if empty(info.paths)
                    if len(info.commit)
                        let reset_commit = info.commit . '^'
                    en
                    continue
                en
                let sub = get(get(get(b:fugitive_files, info.section, {}), info.filename, {}), 'submodule')
                if sub =~# '^S' && info.status ==# 'M'
                    let undo = 'Git checkout ' . fugitive#RevParse('HEAD', FugitiveExtractGitDir(info.paths[0]))[0:10] . ' --'
                elseif sub =~# '^S'
                    let err .= '|echoerr ' . string('fugitive: will not touch submodule ' . string(info.relative[0]))
                    break
                elseif info.status ==# 'D'
                    let undo = 'GRemove'
                elseif info.paths[0] =~# '/$'
                    let err .= '|echoerr ' . string('fugitive: will not delete directory ' . string(info.relative[0]))
                    break
                el
                    let undo = 'Gread ' . s:TreeChomp('hash-object', '-w', '--', info.paths[0])[0:10]
                en
                if info.patch
                    call s:StageApply(info, 1, info.section ==# 'Staged' ? ['--index'] : [])
                elseif sub =~# '^S'
                    if info.section ==# 'Staged'
                        call s:TreeChomp('reset', '--', info.paths[0])
                    en
                    call s:TreeChomp('submodule', 'update', '--', info.paths[0])
                elseif info.status ==# '?'
                    call s:TreeChomp('clean', '-f', '--', info.paths[0])
                elseif a:count == 2
                    if get(b:fugitive_files['Staged'], info.filename, {'status': ''}).status ==# 'D'
                        call delete(FugitiveVimPath(info.paths[0]))
                    el
                        call s:TreeChomp('checkout', '--ours', '--', info.paths[0])
                    en
                elseif a:count == 3
                    if get(b:fugitive_files['Unstaged'], info.filename, {'status': ''}).status ==# 'D'
                        call delete(FugitiveVimPath(info.paths[0]))
                    el
                        call s:TreeChomp('checkout', '--theirs', '--', info.paths[0])
                    en
                elseif info.status =~# '[ADU]' &&
                            \ get(b:fugitive_files[info.section ==# 'Staged' ? 'Unstaged' : 'Staged'], info.filename, {'status': ''}).status =~# '[AU]'
                    if get(g:, 'fugitive_conflict_x', 0)
                        call s:TreeChomp('checkout', info.section ==# 'Unstaged' ? '--ours' : '--theirs', '--', info.paths[0])
                    el
                        if !did_conflict_err
                            let err .= '|echoerr "Use 2X for --ours or 3X for --theirs"'
                            let did_conflict_err = 1
                        en
                        continue
                    en
                elseif info.status ==# 'U'
                    call delete(FugitiveVimPath(info.paths[0]))
                elseif info.status ==# 'A'
                    call s:TreeChomp('rm', '-f', '--', info.paths[0])
                elseif info.section ==# 'Unstaged'
                    call s:TreeChomp('checkout', '--', info.paths[0])
                el
                    call s:TreeChomp('checkout', '@', '--', info.paths[0])
                en
                if len(undo)
                    call add(restore, ':Gsplit ' . s:fnameescape(info.relative[0]) . '|' . undo)
                en
            endfor
        catch /^fugitive:/
            let err .= '|echoerr ' . string(v:exception)
        endtry
        if empty(restore)
            if len(reset_commit) && empty(err)
                call feedkeys(':Git reset ' . reset_commit)
            en
            return err[1:-1]
        en
        exe s:ReloadStatus()
        call s:StageReveal()
        return 'checktime|redraw|echomsg ' . string('To restore, ' . join(restore, '|')) . err
    endf

    fun! s:StageIgnore(lnum1, lnum2, count) abort
        let paths = []
        for info in s:Selection(a:lnum1, a:lnum2)
            call extend(paths, info.relative)
        endfor
        call map(paths, '"/" . v:val')
        if !a:0
            let dir = fugitive#Find('.git/info/')
            if !isdirectory(dir)
                try
                    call mkdir(dir)
                catch
                endtry
            en
        en
        exe 'Gsplit' (a:count ? '.gitignore' : '.git/info/exclude')
        let last = line('$')
        if last == 1 && empty(getline(1))
            call setline(last, paths)
        el
            call append(last, paths)
            exe last + 1
        en
        return ''
    endf

    fun! s:DoToggleHeadHeader(value) abort
        exe 'edit' s:fnameescape(s:Dir())
        call search('\C^index$', 'wc')
    endf

    fun! s:DoToggleHelpHeader(value) abort
        exe 'help fugitive-map'
    endf

    fun! s:DoStagePushHeader(value) abort
        let remote = matchstr(a:value, '\zs[^/]\+\ze/')
        if empty(remote)
            let remote = '.'
        en
        let branch = matchstr(a:value, '\%([^/]\+/\)\=\zs\S\+')
        call feedkeys(':Git push ' . remote . ' ' . branch)
    endf

    fun! s:DoTogglePushHeader(value) abort
        return s:DoStagePushHeader(a:value)
    endf

    fun! s:DoStageUnpushedHeading(heading) abort
        let remote = matchstr(a:heading, 'to \zs[^/]\+\ze/')
        if empty(remote)
            let remote = '.'
        en
        let branch = matchstr(a:heading, 'to \%([^/]\+/\)\=\zs\S\+')
        if branch ==# '*'
            return
        en
        call feedkeys(':Git push ' . remote . ' ' . '@:' . 'refs/heads/' . branch)
    endf

    fun! s:DoToggleUnpushedHeading(heading) abort
        return s:DoStageUnpushedHeading(a:heading)
    endf

    fun! s:DoStageUnpushed(record) abort
        let remote = matchstr(a:record.heading, 'to \zs[^/]\+\ze/')
        if empty(remote)
            let remote = '.'
        en
        let branch = matchstr(a:record.heading, 'to \%([^/]\+/\)\=\zs\S\+')
        if branch ==# '*'
            return
        en
        call feedkeys(':Git push ' . remote . ' ' . a:record.commit . ':' . 'refs/heads/' . branch)
    endf

    fun! s:DoToggleUnpushed(record) abort
        return s:DoStageUnpushed(a:record)
    endf

    fun! s:DoUnstageUnpulledHeading(heading) abort
        call feedkeys(':Git rebase')
    endf

    fun! s:DoToggleUnpulledHeading(heading) abort
        call s:DoUnstageUnpulledHeading(a:heading)
    endf

    fun! s:DoUnstageUnpulled(record) abort
        call feedkeys(':Git rebase ' . a:record.commit)
    endf

    fun! s:DoToggleUnpulled(record) abort
        call s:DoUnstageUnpulled(a:record)
    endf

    fun! s:DoUnstageUnpushed(record) abort
        call feedkeys(':Git -c sequence.editor=true rebase --interactive --autosquash ' . a:record.commit . '^')
    endf

    fun! s:DoToggleStagedHeading(...) abort
        call s:TreeChomp('reset', '-q')
        return 1
    endf

    fun! s:DoUnstageStagedHeading(heading) abort
        return s:DoToggleStagedHeading(a:heading)
    endf

    fun! s:DoToggleUnstagedHeading(...) abort
        call s:TreeChomp('add', '-u')
        return 1
    endf

    fun! s:DoStageUnstagedHeading(heading) abort
        return s:DoToggleUnstagedHeading(a:heading)
    endf

    fun! s:DoToggleUntrackedHeading(...) abort
        call s:TreeChomp('add', '.')
        return 1
    endf

    fun! s:DoStageUntrackedHeading(heading) abort
        return s:DoToggleUntrackedHeading(a:heading)
    endf

    fun! s:DoToggleStaged(record) abort
        if a:record.patch
            return s:StageApply(a:record, 1, ['--cached'])
        el
            call s:TreeChomp(['reset', '-q', '--'] + a:record.paths)
            return 1
        en
    endf

    fun! s:DoUnstageStaged(record) abort
        return s:DoToggleStaged(a:record)
    endf

    fun! s:DoToggleUnstaged(record) abort
        if a:record.patch
            return s:StageApply(a:record, 0, ['--cached'])
        el
            call s:TreeChomp(['add', '-A', '--'] + a:record.paths)
            return 1
        en
    endf

    fun! s:DoStageUnstaged(record) abort
        return s:DoToggleUnstaged(a:record)
    endf

    fun! s:DoUnstageUnstaged(record) abort
        if a:record.status ==# 'A'
            call s:TreeChomp(['reset', '-q', '--'] + a:record.paths)
            return 1
        el
            return -1
        en
    endf

    fun! s:DoToggleUntracked(record) abort
        call s:TreeChomp(['add', '--'] + a:record.paths)
        return 1
    endf

    fun! s:DoStageUntracked(record) abort
        return s:DoToggleUntracked(a:record)
    endf

    fun! s:StagePatch(lnum1,lnum2) abort
        let add = []
        let reset = []
        let intend = []

        for lnum in range(a:lnum1,a:lnum2)
            let info = s:StageInfo(lnum)
            if empty(info.paths) && info.section ==# 'Staged'
                exe  'tab Git reset --patch'
                break
            elseif empty(info.paths) && info.section ==# 'Unstaged'
                exe  'tab Git add --patch'
                break
            elseif empty(info.paths) && info.section ==# 'Untracked'
                exe  'tab Git add --interactive'
                break
            elseif empty(info.paths)
                continue
            en
            exe  lnum
            if info.section ==# 'Staged'
                let reset += info.relative
            elseif info.section ==# 'Untracked'
                let intend += info.paths
            elseif info.status !~# '^D'
                let add += info.relative
            en
        endfor
        try
            if !empty(intend)
                call s:TreeChomp(['add', '--intent-to-add', '--'] + intend)
            en
            if !empty(add)
                exe  "tab Git add --patch -- ".join(map(add,'fnameescape(v:val)'))
            en
            if !empty(reset)
                exe  "tab Git reset --patch -- ".join(map(reset,'fnameescape(v:val)'))
            en
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        return s:ReloadStatus()
    endf

" Section: :Git commit, :Git revert
    fun! s:CommitInteractive(line1, line2, range, bang, mods, options, patch) abort
        let status = s:StatusCommand(a:line1, a:line2, a:range, get(a:options, 'curwin') && a:line2 < 0 ? 0 : a:line2, a:bang, a:mods, '', '', [], a:options)
        let status = len(status) ? status . '|' : ''
        if a:patch
            return status . 'if search("^Unstaged")|exe "normal >"|exe "+"|endif'
        el
            return status . 'if search("^Untracked\\|^Unstaged")|exe "+"|endif'
        en
    endf

    fun! s:CommitSubcommand(line1, line2, range, bang, mods, options) abort
        let argv = copy(a:options.subcommand_args)
        let i = 0
        while get(argv, i, '--') !=# '--'
            if argv[i] =~# '^-[apzsneiovq].'
                call insert(argv, argv[i][0:1])
                let argv[i+1] = '-' . argv[i+1][2:-1]
            el
                let i += 1
            en
        endwhile
        if s:HasOpt(argv, '-i', '--interactive')
            return s:CommitInteractive(a:line1, a:line2, a:range, a:bang, a:mods, a:options, 0)
        elseif s:HasOpt(argv, '-p', '--patch')
            return s:CommitInteractive(a:line1, a:line2, a:range, a:bang, a:mods, a:options, 1)
        el
            return {}
        en
    endf

    fun! s:RevertSubcommand(line1, line2, range, bang, mods, options) abort
        return {'insert_args': ['--edit']}
    endf

    fun! fugitive#CommitComplete(A, L, P, ...) abort
        let dir = a:0 ? a:1 : s:Dir()
        if a:A =~# '^--fixup=\|^--squash='
            let commits = s:LinesError([dir, 'log', '--pretty=format:%s', '@{upstream}..'])[0]
            let pre = matchstr(a:A, '^--\w*=''\=') . ':/^'
            if pre =~# "'"
                call map(commits, 'pre . string(tr(v:val, "|\"^$*[]", "......."))[1:-1]')
                call filter(commits, 'strpart(v:val, 0, strlen(a:A)) ==# a:A')
                return commits
            el
                return s:FilterEscape(map(commits, 'pre . tr(v:val, "\\ !^$*?[]()''\"`&;<>|#", "....................")'), a:A)
            en
        el
            return s:CompleteSub('commit', a:A, a:L, a:P, function('fugitive#CompletePath'), a:000)
        en
        return []
    endf

    fun! fugitive#RevertComplete(A, L, P, ...) abort
        return s:CompleteSub('revert', a:A, a:L, a:P, function('s:CompleteRevision'), a:000)
    endf

" Section: :Git merge, :Git rebase, :Git pull

    fun! fugitive#MergeComplete(A, L, P, ...) abort
        return s:CompleteSub('merge', a:A, a:L, a:P, function('s:CompleteRevision'), a:000)
    endf

    fun! fugitive#RebaseComplete(A, L, P, ...) abort
        return s:CompleteSub('rebase', a:A, a:L, a:P, function('s:CompleteRevision'), a:000)
    endf

    fun! fugitive#PullComplete(A, L, P, ...) abort
        return s:CompleteSub('pull', a:A, a:L, a:P, function('s:CompleteRemote'), a:000)
    endf

    fun! s:MergeSubcommand(line1, line2, range, bang, mods, options) abort
        if empty(a:options.subcommand_args) && (
                    \ filereadable(fugitive#Find('.git/MERGE_MSG', a:options)) ||
                    \ isdirectory(fugitive#Find('.git/rebase-apply', a:options)) ||
                    \  !empty(s:TreeChomp([a:options.git_dir, 'diff-files', '--diff-filter=U'])))
            return 'echoerr ":Git merge for loading conflicts has been removed in favor of :Git mergetool"'
        en
        return {}
    endf

    fun! s:RebaseSubcommand(line1, line2, range, bang, mods, options) abort
        let args = a:options.subcommand_args
        if s:HasOpt(args, '--autosquash') && !s:HasOpt(args, '-i', '--interactive')
            return {'env': {'GIT_SEQUENCE_EDITOR': 'true'}, 'insert_args': ['--interactive']}
        en
        return {}
    endf

" Section: :Git bisect

    fun! s:CompleteBisect(A, L, P, ...) abort
        let bisect_subcmd = matchstr(a:L, '\u\w*[! ] *.\{-\}\s\@<=\zs[^-[:space:]]\S*\ze ')
        if empty(bisect_subcmd)
            let subcmds = ['start', 'bad', 'new', 'good', 'old', 'terms', 'skip', 'next', 'reset', 'replay', 'log', 'run']
            return s:FilterEscape(subcmds, a:A)
        en
        let dir = a:0 ? a:1 : s:Dir()
        return fugitive#CompleteObject(a:A, dir)
    endf

    function fugitive#BisectComplete(A, L, P, ...) abort
        return s:CompleteSub('bisect', a:A, a:L, a:P, function('s:CompleteBisect'), a:000)
    endf

" Section: :Git difftool, :Git mergetool

    fun! s:ToolItems(state, from, to, offsets, text, ...) abort
        let items = []
        for i in range(len(a:state.diff))
            let diff = a:state.diff[i]
            let path = (i == len(a:state.diff) - 1) ? a:to : a:from
            if empty(path)
                return []
            en
            let item = {
                        \ 'valid': a:0 ? a:1 : 1,
                        \ 'filename': diff.filename . FugitiveVimPath(path),
                        \ 'lnum': matchstr(get(a:offsets, i), '\d\+'),
                        \ 'text': a:text}
            if len(get(diff, 'module', ''))
                let item.module = diff.module . path
            en
            call add(items, item)
        endfor
        let items[-1].context = {'diff': items[0:-2]}
        return [items[-1]]
    endf

    fun! s:ToolToFrom(str) abort
        if a:str =~# ' => '
            let str = a:str =~# '{.* => .*}' ? a:str : '{' . a:str . '}'
            return [substitute(str, '{.* => \(.*\)}', '\1', ''),
                        \ substitute(str, '{\(.*\) => .*}', '\1', '')]
        el
            return [a:str, a:str]
        en
    endf

    fun! s:ToolParse(state, line) abort
        if type(a:line) !=# type('') || a:state.mode ==# 'hunk' && a:line =~# '^[ +-]'
            return []
        elseif a:line =~# '^diff '
            let a:state.mode = 'diffhead'
            let a:state.from = ''
            let a:state.to = ''
        elseif a:state.mode ==# 'diffhead' && a:line =~# '^--- [^/]'
            let a:state.from = a:line[4:-1]
            let a:state.to = a:state.from
        elseif a:state.mode ==# 'diffhead' && a:line =~# '^+++ [^/]'
            let a:state.to = a:line[4:-1]
            if empty(get(a:state, 'from', ''))
                let a:state.from = a:state.to
            en
        elseif a:line[0] ==# '@'
            let a:state.mode = 'hunk'
            if has_key(a:state, 'from')
                let offsets = split(matchstr(a:line, '^@\+ \zs[-+0-9, ]\+\ze @'), ' ')
                return s:ToolItems(a:state, a:state.from, a:state.to, offsets, matchstr(a:line, ' @@\+ \zs.*'))
            en
        elseif a:line =~# '^\* Unmerged path .'
            let file = a:line[16:-1]
            return s:ToolItems(a:state, file, file, [], '')
        elseif a:line =~# '^[A-Z]\d*\t.\|^:.*\t.'
            " --raw, --name-status
            let [status; files] = split(a:line, "\t")
            return s:ToolItems(a:state, files[0], files[-1], [], a:state.name_only ? '' : status)
        elseif a:line =~# '^ \S.* |'
            " --stat
            let [_, to, changes; __] = matchlist(a:line, '^ \(.\{-\}\) \+|\zs \(.*\)$')
            let [to, from] = s:ToolToFrom(to)
            return s:ToolItems(a:state, from, to, [], changes)
        elseif a:line =~# '^ *\([0-9.]\+%\) .'
            " --dirstat
            let [_, changes, to; __] = matchlist(a:line, '^ *\([0-9.]\+%\) \(.*\)')
            return s:ToolItems(a:state, to, to, [], changes)
        elseif a:line =~# '^\(\d\+\|-\)\t\(\d\+\|-\)\t.'
            " --numstat
            let [_, add, remove, to; __] = matchlist(a:line, '^\(\d\+\|-\)\t\(\d\+\|-\)\t\(.*\)')
            let [to, from] = s:ToolToFrom(to)
            return s:ToolItems(a:state, from, to, [], add ==# '-' ? 'Binary file' : '+' . add . ' -' . remove, add !=# '-')
        elseif a:state.mode !=# 'diffhead' && a:state.mode !=# 'hunk' && len(a:line) || a:line =~# '^git: \|^usage: \|^error: \|^fatal: '
            return [{'text': a:line}]
        en
        return []
    endf

    fun! s:ToolStream(line1, line2, range, bang, mods, options, args, state) abort
        let i = 0
        let argv = copy(a:args)
        let prompt = 1
        let state = a:state
        while i < len(argv)
            let match = matchlist(argv[i], '^\(-[a-zABDFH-KN-RT-Z]\)\ze\(.*\)')
            if len(match) && len(match[2])
                call insert(argv, match[1])
                let argv[i+1] = '-' . match[2]
                continue
            en
            let arg = argv[i]
            if arg =~# '^-t$\|^--tool=\|^--tool-help$\|^--help$'
                return {}
            elseif arg =~# '^-y$\|^--no-prompt$'
                let prompt = 0
                call remove(argv, i)
                continue
            elseif arg ==# '--prompt'
                let prompt = 1
                call remove(argv, i)
                continue
            elseif arg =~# '^--\%(no-\)\=\(symlinks\|trust-exit-code\|gui\)$'
                call remove(argv, i)
                continue
            elseif arg ==# '--'
                break
            en
            let i += 1
        endwhile
        call fugitive#Autowrite()
        let a:state.mode = 'init'
        let a:state.from = ''
        let a:state.to = ''
        let exec = s:UserCommandList({'git': a:options.git, 'git_dir': a:options.git_dir}) + ['-c', 'diff.context=0']
        let exec += a:options.flags + ['--no-pager', 'diff', '--no-ext-diff', '--no-color', '--no-prefix'] + argv
        if prompt
            let title = ':Git ' . s:fnameescape(a:options.flags + [a:options.subcommand] + a:options.subcommand_args)
            return s:QuickfixStream(get(a:options, 'curwin') && a:line2 < 0 ? 0 : a:line2, 'difftool', title, exec, !a:bang, a:mods, s:function('s:ToolParse'), a:state)
        el
            let filename = ''
            let cmd = []
            let tabnr = tabpagenr() + 1
            for line in s:SystemList(exec)[0]
                for item in s:ToolParse(a:state, line)
                    if len(get(item, 'filename', '')) && item.filename != filename
                        call add(cmd, 'tabedit ' . s:fnameescape(item.filename))
                        for i in reverse(range(len(get(item.context, 'diff', []))))
                            call add(cmd, (i ? 'rightbelow' : 'leftabove') . ' vertical Gdiffsplit! ' . s:fnameescape(item.context.diff[i].filename))
                        endfor
                        call add(cmd, 'wincmd =')
                        let filename = item.filename
                    en
                endfor
            endfor
            return join(cmd, '|') . (empty(cmd) ? '' : '|' . tabnr . 'tabnext')
        en
    endf

    fun! s:MergetoolSubcommand(line1, line2, range, bang, mods, options) abort
        let dir = a:options.git_dir
        exe s:DirCheck(dir)
        let i = 0
        let prompt = 1
        let cmd = ['diff', '--diff-filter=U']
        let state = {'name_only': 0}
        let state.diff = [{'prefix': ':2:', 'module': ':2:'}, {'prefix': ':3:', 'module': ':3:'}, {'prefix': ':(top)'}]
        call map(state.diff, 'extend(v:val, {"filename": fugitive#Find(v:val.prefix, dir)})')
        return s:ToolStream(a:line1, a:line2, a:range, a:bang, a:mods, a:options, ['--diff-filter=U'] + a:options.subcommand_args, state)
    endf

    fun! s:DifftoolSubcommand(line1, line2, range, bang, mods, options) abort
        let dir = s:Dir(a:options)
        exe s:DirCheck(dir)
        let i = 0
        let argv = copy(a:options.subcommand_args)
        let commits = []
        let cached = 0
        let reverse = 1
        let prompt = 1
        let state = {'name_only': 0}
        let merge_base_against = {}
        let dash = (index(argv, '--') > i ? ['--'] : [])
        while i < len(argv)
            let match = matchlist(argv[i], '^\(-[a-zABDFH-KN-RT-Z]\)\ze\(.*\)')
            if len(match) && len(match[2])
                call insert(argv, match[1])
                let argv[i+1] = '-' . match[2]
                continue
            en
            let arg = argv[i]
            if arg ==# '--cached'
                let cached = 1
            elseif arg ==# '-R'
                let reverse = 1
            elseif arg ==# '--name-only'
                let state.name_only = 1
                let argv[0] = '--name-status'
            elseif arg ==# '--'
                break
            elseif arg !~# '^-\|^\.\.\=\%(/\|$\)'
                let parsed = s:LinesError(['rev-parse', '--revs-only', substitute(arg, ':.*', '', '')] + dash)[0]
                call map(parsed, '{"uninteresting": v:val =~# "^\\^", "prefix": substitute(v:val, "^\\^", "", "") . ":"}')
                let merge_base_against = {}
                if arg =~# '\.\.\.' && len(parsed) > 2
                    let display = map(split(arg, '\.\.\.', 1), 'empty(v:val) ? "@" : v:val')
                    if len(display) == 2
                        let parsed[0].module = display[1] . ':'
                        let parsed[1].module = display[0] . ':'
                    en
                    let parsed[2].module = arg . ':'
                    if empty(commits)
                        let merge_base_against = parsed[0]
                        let parsed = [parsed[2]]
                    en
                elseif arg =~# '\.\.' && len(parsed) == 2
                    let display = map(split(arg, '\.\.', 1), 'empty(v:val) ? "@" : v:val')
                    if len(display) == 2
                        let parsed[0].module = display[0] . ':'
                        let parsed[1].module = display[1] . ':'
                    en
                elseif len(parsed) == 1
                    let parsed[0].module = arg . ':'
                en
                call extend(commits, parsed)
            en
            let i += 1
        endwhile
        if len(merge_base_against)
            call add(commits, merge_base_against)
        en
        let commits = filter(copy(commits), 'v:val.uninteresting') + filter(commits, '!v:val.uninteresting')
        if cached
            if empty(commits)
                call add(commits, {'prefix': '@:', 'module': '@:'})
            en
            call add(commits, {'prefix': ':0:', 'module': ':0:'})
        elseif len(commits) < 2
            call add(commits, {'prefix': ':(top)'})
            if len(commits) < 2
                call insert(commits, {'prefix': ':0:', 'module': ':0:'})
            en
        en
        if reverse
            let commits = [commits[-1]] + repeat([commits[0]], len(commits) - 1)
            call reverse(commits)
        en
        if len(commits) > 2
            call add(commits, remove(commits, 0))
        en
        call map(commits, 'extend(v:val, {"filename": fugitive#Find(v:val.prefix, dir)})')
        let state.diff = commits
        return s:ToolStream(a:line1, a:line2, a:range, a:bang, a:mods, a:options, argv, state)
    endf

" Section: :Ggrep, :Glog

    if !exists('g:fugitive_summary_format')
        let g:fugitive_summary_format = '%s'
    en

    fun! fugitive#GrepComplete(A, L, P) abort
        return s:CompleteSub('grep', a:A, a:L, a:P)
    endf

    fun! fugitive#LogComplete(A, L, P) abort
        return s:CompleteSub('log', a:A, a:L, a:P)
    endf

    fun! s:GrepParseLine(options, quiet, dir, line) abort
        if !a:quiet
            echo a:line
        en
        let entry = {'valid': 1}
        let match = matchlist(a:line, '^\(.\{-\}\):\([1-9]\d*\):\([1-9]\d*:\)\=\(.*\)$')
        if a:line =~# '^git: \|^usage: \|^error: \|^fatal: \|^BUG: '
            return {'text': a:line}
        elseif len(match)
            let entry.module = match[1]
            let entry.lnum = +match[2]
            let entry.col = +match[3]
            let entry.text = match[4]
        el
            let entry.module = matchstr(a:line, '\CBinary file \zs.*\ze matches$')
            if len(entry.module)
                let entry.text = 'Binary file'
                let entry.valid = 0
            en
        en
        if empty(entry.module) && !a:options.line_number
            let match = matchlist(a:line, '^\(.\{-\}\):\(.*\)$')
            if len(match)
                let entry.module = match[1]
                let entry.pattern = '\M^' . escape(match[2], '\.^$/') . '$'
            en
        en
        if empty(entry.module) && a:options.name_count && a:line =~# ':\d\+$'
            let entry.text = matchstr(a:line, '\d\+$')
            let entry.module = strpart(a:line, 0, len(a:line) - len(entry.text) - 1)
        en
        if empty(entry.module) && a:options.name_only
            let entry.module = a:line
        en
        if empty(entry.module)
            return {'text': a:line}
        en
        if entry.module !~# ':'
            let entry.filename = a:options.prefix . entry.module
        el
            let entry.filename = fugitive#Find(entry.module, a:dir)
        en
        return entry
    endf

    let s:grep_combine_flags = '[aiIrhHEGPFnlLzocpWq]\{-\}'
    fun! s:GrepOptions(args, dir) abort
        let options = {'name_only': 0, 'name_count': 0, 'line_number': 0}
        let tree = s:Tree(a:dir)
        let prefix = empty(tree) ? fugitive#Find(':0:', a:dir) :
                    \ s:cpath(getcwd(), tree) ? '' : FugitiveVimPath(tree . '/')
        let options.prefix = prefix
        for arg in a:args
            if arg ==# '--'
                break
            en
            if arg =~# '^\%(-' . s:grep_combine_flags . 'c\|--count\)$'
                let options.name_count = 1
            en
            if arg =~# '^\%(-' . s:grep_combine_flags . 'n\|--line-number\)$'
                let options.line_number = 1
            elseif arg =~# '^\%(--no-line-number\)$'
                let options.line_number = 0
            en
            if arg =~# '^\%(-' . s:grep_combine_flags . '[lL]\|--files-with-matches\|--name-only\|--files-without-match\)$'
                let options.name_only = 1
            en
            if arg ==# '--cached'
                let options.prefix = fugitive#Find(':0:', a:dir)
            elseif arg ==# '--no-cached'
                let options.prefix = prefix
            en
        endfor
        return options
    endf

    fun! s:GrepCfile(result) abort
        let options = s:GrepOptions(a:result.args, a:result)
        let entry = s:GrepParseLine(options, 1, a:result, getline('.'))
        if get(entry, 'col')
            return [entry.filename, entry.lnum, "norm!" . entry.col . "|"]
        elseif has_key(entry, 'lnum')
            return [entry.filename, entry.lnum]
        elseif has_key(entry, 'pattern')
            return [entry.filename, '', 'silent /' . entry.pattern]
        elseif has_key(entry, 'filename')
            return [entry.filename]
        el
            return []
        en
    endf

    fun! s:GrepSubcommand(line1, line2, range, bang, mods, options) abort
        let args = copy(a:options.subcommand_args)
        let handle = -1
        let quiet = 0
        let i = 0
        while i < len(args) && args[i] !=# '--'
            let partition = matchstr(args[i], '^-' . s:grep_combine_flags . '\ze[qzO]')
            if len(partition) > 1
                call insert(args, '-' . strpart(args[i], len(partition)), i+1)
                let args[i] = partition
            elseif args[i] =~# '^\%(-' . s:grep_combine_flags . '[eABC]\|--max-depth\|--context\|--after-context\|--before-context\|--threads\)$'
                let i += 1
            elseif args[i] =~# '^\%(-O\|--open-files-in-pager\)$'
                let handle = 1
                call remove(args, i)
                continue
            elseif args[i] =~# '^\%(-O\|--open-files-in-pager=\)'
                let handle = 0
            elseif args[i] =~# '^-[qz].'
                let args[i] = '-' . args[i][2:-1]
                let quiet = 1
            elseif args[i] =~# '^\%(-[qz]\|--quiet\)$'
                let quiet = 1
                call remove(args, i)
                continue
            elseif args[i] =~# '^--no-quiet$'
                let quiet = 0
            elseif args[i] =~# '^\%(--heading\)$'
                call remove(args, i)
                continue
            en
            let i += 1
        endwhile
        if handle < 0 ? !quiet : !handle
            return {}
        en
        call fugitive#Autowrite()
        let listnr = get(a:options, 'curwin') && a:line2 < 0 ? 0 : a:line2
        if s:HasOpt(args, '--no-line-number')
            let lc = []
        el
            let lc = fugitive#GitVersion(2, 19) ? ['-n', '--column'] : ['-n']
        en
        let cmd = ['grep', '--no-color', '--full-name'] + lc
        let dir = s:Dir(a:options)
        let options = s:GrepOptions(lc + args, dir)
        if listnr > 0
            exe listnr 'wincmd w'
        el
            call s:BlurStatus()
        en
        let title = (listnr < 0 ? ':Ggrep ' : ':Glgrep ') . s:fnameescape(args)
        call s:QuickfixCreate(listnr, {'title': title})
        let tempfile = tempname()
        let state = {
                    \ 'git': a:options.git,
                    \ 'flags': a:options.flags,
                    \ 'args': cmd + args,
                    \ 'dir': s:GitDir(a:options),
                    \ 'git_dir': s:GitDir(a:options),
                    \ 'cwd': s:UserCommandCwd(a:options),
                    \ 'filetype': 'git',
                    \ 'mods': s:Mods(a:mods),
                    \ 'file': s:Resolve(tempfile)}
        let event = listnr < 0 ? 'grep-fugitive' : 'lgrep-fugitive'
        exe s:DoAutocmd('QuickFixCmdPre ' . event)
        try
            if !quiet && &more
                let more = 1
                set nomore
            en
            if !quiet
                echo title
            en
            let list = s:SystemList(s:UserCommandList(a:options) + cmd + args)[0]
            call writefile(list + [''], tempfile, 'b')
            call s:RunSave(state)
            call map(list, 's:GrepParseLine(options, ' . quiet . ', dir, v:val)')
            call s:QuickfixSet(listnr, list, 'a')
            let press_enter_shortfall = &cmdheight - len(list)
            if press_enter_shortfall > 0 && !quiet
                echo repeat("\n", press_enter_shortfall - 1)
            en
        finally
            if exists('l:more')
                let &more = more
            en
        endtry
        call s:RunFinished(state)
        exe s:DoAutocmd('QuickFixCmdPost ' . event)
        if quiet
            let bufnr = bufnr('')
            exe s:QuickfixOpen(listnr, a:mods)
            if bufnr != bufnr('') && !a:bang
                wincmd p
            en
        end
        if !a:bang && !empty(list)
            return 'silent ' . (listnr < 0 ? 'c' : 'l').'first'
        el
            return ''
        en
    endf

    fun! fugitive#GrepCommand(line1, line2, range, bang, mods, arg) abort
        return fugitive#Command(a:line1, a:line2, a:range, a:bang, a:mods,
                    \ "grep -O " . a:arg)
    endf

    let s:log_diff_context = '{"filename": fugitive#Find(v:val . from, a:dir), "lnum": get(offsets, v:key), "module": strpart(v:val, 0, len(a:state.base_module)) . from}'

    fun! s:LogFlushQueue(state, dir) abort
        let queue = remove(a:state, 'queue')
        if a:state.child_found && get(a:state, 'ignore_commit')
            call remove(queue, 0)
        elseif len(queue) && len(a:state.target) && len(get(a:state, 'parents', []))
            let from = substitute(a:state.target, '^/', ':', '')
            let offsets = []
            let queue[0].context.diff = map(copy(a:state.parents), s:log_diff_context)
        en
        if len(queue) && queue[-1] ==# {'text': ''}
            call remove(queue, -1)
        en
        return queue
    endf

    fun! s:LogParse(state, dir, prefix, line) abort
        if a:state.mode ==# 'hunk' && a:line =~# '^[-+ ]'
            return []
        en
        let list = matchlist(a:line, '^\%(fugitive \(.\{-\}\)\t\|commit \|From \)\=\(\x\{40,\}\)\%( \(.*\)\)\=$')
        if len(list)
            let queue = s:LogFlushQueue(a:state, a:dir)
            let a:state.mode = 'commit'
            let a:state.base = a:prefix . list[2]
            if len(list[1])
                let [a:state.base_module; a:state.parents] = split(list[1], ' ')
            el
                let a:state.base_module = list[2]
                let a:state.parents = []
            en
            let a:state.message = list[3]
            let a:state.from = ''
            let a:state.to = ''
            let context = {}
            let a:state.queue = [{
                        \ 'valid': 1,
                        \ 'context': context,
                        \ 'filename': a:state.base . a:state.target,
                        \ 'module': a:state.base_module . substitute(a:state.target, '^/', ':', ''),
                        \ 'text': a:state.message}]
            let a:state.child_found = 0
            return queue
        elseif type(a:line) == type(0)
            return s:LogFlushQueue(a:state, a:dir)
        elseif a:line =~# '^diff'
            let a:state.mode = 'diffhead'
            let a:state.from = ''
            let a:state.to = ''
        elseif a:state.mode ==# 'diffhead' && a:line =~# '^--- \w/'
            let a:state.from = a:line[6:-1]
            let a:state.to = a:state.from
        elseif a:state.mode ==# 'diffhead' && a:line =~# '^+++ \w/'
            let a:state.to = a:line[6:-1]
            if empty(get(a:state, 'from', ''))
                let a:state.from = a:state.to
            en
        elseif a:line =~# '^@@[^@]*+\d' && len(get(a:state, 'to', '')) && has_key(a:state, 'base')
            let a:state.mode = 'hunk'
            if empty(a:state.target) || a:state.target ==# '/' . a:state.to
                if !a:state.child_found && len(a:state.queue) && a:state.queue[-1] ==# {'text': ''}
                    call remove(a:state.queue, -1)
                en
                let a:state.child_found = 1
                let offsets = map(split(matchstr(a:line, '^@\+ \zs[-+0-9, ]\+\ze @'), ' '), '+matchstr(v:val, "\\d\\+")')
                let context = {}
                if len(a:state.parents)
                    let from = ":" . a:state.from
                    let context.diff = map(copy(a:state.parents), s:log_diff_context)
                en
                call add(a:state.queue, {
                            \ 'valid': 1,
                            \ 'context': context,
                            \ 'filename': FugitiveVimPath(a:state.base . '/' . a:state.to),
                            \ 'module': a:state.base_module . ':' . a:state.to,
                            \ 'lnum': offsets[-1],
                            \ 'text': a:state.message . matchstr(a:line, ' @@\+ .\+')})
            en
        elseif a:state.follow &&
                    \ a:line =~# '^ \%(mode change \d\|\%(create\|delete\) mode \d\|\%(rename\|copy\|rewrite\) .* (\d\+%)$\)'
            let rename = matchstr(a:line, '^ \%(copy\|rename\) \zs.* => .*\ze (\d\+%)$')
            if len(rename)
                let rename = rename =~# '{.* => .*}' ? rename : '{' . rename . '}'
                if a:state.target ==# simplify('/' . substitute(rename, '{.* => \(.*\)}', '\1', ''))
                    let a:state.target = simplify('/' . substitute(rename, '{\(.*\) => .*}', '\1', ''))
                en
            en
            if !get(a:state, 'ignore_summary')
                call add(a:state.queue, {'text': a:line})
            en
        elseif a:state.mode ==# 'commit' || a:state.mode ==# 'init'
            call add(a:state.queue, {'text': a:line})
        en
        return []
    endf

    fun! fugitive#LogCommand(line1, count, range, bang, mods, args, type) abort
        let dir = s:Dir()
        exe s:DirCheck(dir)
        let listnr = a:type =~# '^l' ? 0 : -1
        let [args, after] = s:SplitExpandChain('log ' . a:args, s:Tree(dir))
        call remove(args, 0)
        let split = index(args, '--')
        if split > 0
            let paths = args[split : -1]
            let args = args[0 : split - 1]
        elseif split == 0
            let paths = args
            let args = []
        el
            let paths = []
        en
        if a:line1 == 0 && a:count
            let path = fugitive#Path(bufname(a:count), '/', dir)
            let titlepre = ':0,' . a:count
        elseif a:count >= 0
            let path = fugitive#Path(@%, '/', dir)
            let titlepre = a:count == 0 ? ':0,' . bufnr('') : ':'
        el
            let titlepre = ':'
            let path = ''
        en
        let range = ''
        let extra_args = []
        let extra_paths = []
        let state = {'mode': 'init', 'child_found': 0, 'queue': [], 'follow': 0}
        if path =~# '^/\.git\%(/\|$\)\|^$'
            let path = ''
        elseif a:line1 == 0
            let range = "0," . (a:count ? a:count : bufnr(''))
            let extra_paths = ['.' . path]
            if (empty(paths) || paths ==# ['--']) && !s:HasOpt(args, '--no-follow')
                let state.follow = 1
                if !s:HasOpt(args, '--follow')
                    call insert(extra_args, '--follow')
                en
                if !s:HasOpt(args, '--summary')
                    call insert(extra_args, '--summary')
                    let state.ignore_summary = 1
                en
            en
            let state.ignore_commit = 1
        elseif a:count > 0
            if !s:HasOpt(args, '--merges', '--no-merges')
                call insert(extra_args, '--no-merges')
            en
            call add(args, '-L' . a:line1 . ',' . a:count . ':' . path[1:-1])
            let state.ignore_commit = 1
        en
        if len(path) && empty(filter(copy(args), 'v:val =~# "^[^-]"'))
            let owner = s:Owner(@%, dir)
            if len(owner)
                call add(args, owner . (owner =~# '^\x\{40,}' ? '' : '^{}'))
            en
        en
        if empty(extra_paths)
            let path = ''
        en
        if s:HasOpt(args, '-g', '--walk-reflogs')
            let format = "%gd %P\t%H %gs"
        el
            let format = "%h %P\t%H " . g:fugitive_summary_format
        en
        let cmd = ['--no-pager']
        call extend(cmd, ['-c', 'diff.context=0', '-c', 'diff.noprefix=false', 'log'] +
                    \ ['--no-color', '--no-ext-diff', '--pretty=format:fugitive ' . format] +
                    \ args + extra_args + paths + extra_paths)
        let state.target = path
        let title = titlepre . (listnr < 0 ? 'Gclog ' : 'Gllog ') . s:fnameescape(args + paths)
        return s:QuickfixStream(listnr, 'log', title, s:UserCommandList(dir) + cmd, !a:bang, a:mods, s:function('s:LogParse'), state, dir, s:DirUrlPrefix(dir)) . after
    endf

" Section: :Gedit, :Gpedit, :Gsplit, :Gvsplit, :Gtabedit, :Gread

    fun! s:UsableWin(nr) abort
        return a:nr && !getwinvar(a:nr, '&previewwindow') && !getwinvar(a:nr, '&winfixwidth') &&
                    \ (empty(getwinvar(a:nr, 'fugitive_status')) || getbufvar(winbufnr(a:nr), 'fugitive_type') !=# 'index') &&
                    \ index(['gitrebase', 'gitcommit'], getbufvar(winbufnr(a:nr), '&filetype')) < 0 &&
                    \ index(['nofile','help','quickfix', 'terminal'], getbufvar(winbufnr(a:nr), '&buftype')) < 0
    endf

    fun! s:ArgSplit(string) abort
        let string = a:string
        let args = []
        while string =~# '\S'
            let arg = matchstr(string, '^\s*\%(\\.\|[^[:space:]]\)\+')
            let string = strpart(string, len(arg))
            let arg = substitute(arg, '^\s\+', '', '')
            call add(args, substitute(arg, '\\\+[|" ]', '\=submatch(0)[len(submatch(0))/2 : -1]', 'g'))
        endwhile
        return args
    endf

    fun! s:PlusEscape(string) abort
        return substitute(a:string, '\\*[|" ]', '\=repeat("\\", len(submatch(0))).submatch(0)', 'g')
    endf

    fun! s:OpenParse(string, wants_cmd) abort
        let opts = []
        let cmds = []
        let args = s:ArgSplit(a:string)
        while !empty(args)
            if args[0] =~# '^++'
                call add(opts, ' ' . s:PlusEscape(remove(args, 0)))
            elseif a:wants_cmd && args[0] =~# '^+'
                call add(cmds, remove(args, 0)[1:-1])
            el
                break
            en
        endwhile
        if len(args) && args !=# ['>:']
            let file = join(args)
            if file ==# '-'
                let result = fugitive#Result()
                if has_key(result, 'file')
                    let file = s:fnameescape(result.file)
                el
                    throw 'fugitive: no previous command output'
                en
            en
        elseif empty(expand('%'))
            let file = ''
        elseif empty(s:DirCommitFile(@%)[1]) && s:Relative('./') !~# '^\./\.git\>'
            let file = '>:0'
        el
            let file = '>'
        en
        let dir = s:Dir()
        let efile = s:Expand(file)
        let url = s:Generate(efile, dir)

        if a:wants_cmd && file[0] ==# '>' && efile[0] !=# '>' && get(b:, 'fugitive_type', '') isnot# 'tree' && &filetype !=# 'netrw'
            let line = line('.')
            if expand('%:p') !=# url
                let diffcmd = 'diff'
                let from = s:DirRev(@%)[1]
                let to = s:DirRev(url)[1]
                if empty(from) && empty(to)
                    let diffcmd = 'diff-files'
                    let args = ['--', expand('%:p'), url]
                elseif empty(to)
                    let args = [from, '--', url]
                elseif empty(from)
                    let args = [to, '--', expand('%:p')]
                    let reverse = 1
                el
                    let args = [from, to]
                en
                let [res, exec_error] = s:LinesError([dir, diffcmd, '-U0'] + args)
                if !exec_error
                    call filter(res, 'v:val =~# "^@@ "')
                    call map(res, 'substitute(v:val, ''[-+]\d\+\zs '', ",1 ", "g")')
                    call map(res, 'matchlist(v:val, ''^@@ -\(\d\+\),\(\d\+\) +\(\d\+\),\(\d\+\) @@'')[1:4]')
                    if exists('reverse')
                        call map(res, 'v:val[2:3] + v:val[0:1]')
                    en
                    call filter(res, 'v:val[0] < '.line('.'))
                    let hunk = get(res, -1, [0,0,0,0])
                    if hunk[0] + hunk[1] > line('.')
                        let line = hunk[2] + max([1 - hunk[3], 0])
                    el
                        let line = hunk[2] + max([hunk[3], 1]) + line('.') - hunk[0] - max([hunk[1], 1])
                    en
                en
            en
            call insert(cmds, line)
        en

        let pre = join(opts, '')
        if len(cmds) > 1
            let pre .= ' +' . s:PlusEscape(join(map(cmds, '"exe ".string(v:val)'), '|'))
        elseif len(cmds)
            let pre .= ' +' . s:PlusEscape(cmds[0])
        en
        return [url, pre]
    endf

    fun! fugitive#DiffClose() abort
        let mywinnr = winnr()
        for winnr in [winnr('#')] + range(winnr('$'),1,-1)
            if winnr != mywinnr && getwinvar(winnr,'&diff')
                exe  winnr.'wincmd w'
                close
                if winnr('$') > 1
                    wincmd p
                en
            en
        endfor
        diffoff!
    endf

    fun! s:BlurStatus() abort
        if (&previewwindow || exists('w:fugitive_status')) && get(b:,'fugitive_type', '') ==# 'index'
            let winnrs = filter([winnr('#')] + range(1, winnr('$')), 's:UsableWin(v:val)')
            if len(winnrs)
                exe winnrs[0].'wincmd w'
            el
                belowright new
            en
            if &diff
                call fugitive#DiffClose()
            en
        en
    endf

    let s:bang_edits = {'split': 'Git', 'vsplit': 'vertical Git', 'tabedit': 'tab Git', 'pedit': 'Git!'}
    fun! fugitive#Open(cmd, bang, mods, arg, ...) abort
        exe s:VersionCheck()
        if a:bang
            return 'echoerr ' . string(':G' . a:cmd . '! for temp buffer output has been replaced by :' . get(s:bang_edits, a:cmd, 'Git') . ' --paginate')
        en

        let mods = s:Mods(a:mods)
        try
            let [file, pre] = s:OpenParse(a:arg, 1)
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        if file !~# '^\a\a\+:' && !(has('win32') && file =~# '^\a:/$')
            let file = substitute(file, '.\zs' . (has('win32') ? '[\/]' : '/') . '$', '', '')
        en
        if a:cmd ==# 'edit'
            call s:BlurStatus()
        en
        return mods . a:cmd . pre . ' ' . s:fnameescape(file)
    endf

    fun! s:ReadPrepare(line1, count, range, mods) abort
        let mods = s:Mods(a:mods)
        let after = a:count
        if a:count < 0
            let delete = 'silent 1,' . line('$') . 'delete_|'
            let after = line('$')
        elseif a:range == 2
            let delete = 'silent ' . a:line1 . ',' . a:count . 'delete_|'
        el
            let delete = ''
        en
        if foldlevel(after)
            let pre = after . 'foldopen!|'
        el
            let pre = ''
        en
        return [pre . 'keepalt ' . mods . after . 'read', '|' . delete . 'diffupdate' . (a:count < 0 ? '|' . line('.') : '')]
    endf

    fun! fugitive#ReadCommand(line1, count, range, bang, mods, arg, ...) abort
        exe s:VersionCheck()
        if a:bang
            return 'echoerr ' . string(':Gread! for temp buffer output has been replaced by :{range}Git! --paginate')
        en
        let [read, post] = s:ReadPrepare(a:line1, a:count, a:range, a:mods)
        try
            let [file, pre] = s:OpenParse(a:arg, 0)
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        if file =~# '^fugitive:' && a:count is# 0
            return 'exe ' .string('keepalt ' . s:Mods(a:mods) . fugitive#FileReadCmd(file, 0, pre)) . '|diffupdate'
        en
        return read . ' ' . pre . ' ' . s:fnameescape(file) . post
    endf

    fun! fugitive#EditComplete(A, L, P) abort
        if a:A =~# '^>'
            return map(s:FilterEscape(s:CompleteHeads(s:Dir()), a:A[1:-1]), "'>' . v:val")
        el
            return fugitive#CompleteObject(a:A, a:L, a:P)
        en
    endf

    fun! fugitive#ReadComplete(A, L, P) abort
        if a:L =~# '^\w\+!'
            return fugitive#Complete(a:A, a:L, a:P)
        el
            return fugitive#EditComplete(a:A, a:L, a:P)
        en
    endf

" Section: :Gwrite, :Gwq

    fun! fugitive#WriteCommand(line1, line2, range, bang, mods, arg, ...) abort
        exe s:VersionCheck()
        if s:cpath(expand('%:p'), fugitive#Find('.git/COMMIT_EDITMSG')) && empty(a:arg)
            return (empty($GIT_INDEX_FILE) ? 'write|bdelete' : 'wq') . (a:bang ? '!' : '')
        elseif get(b:, 'fugitive_type', '') ==# 'index' && empty(a:arg)
            return 'Git commit'
        elseif &buftype ==# 'nowrite' && getline(4) =~# '^[+-]\{3\} '
            return 'echoerr ' . string('fugitive: :Gwrite from :Git diff has been removed in favor of :Git add --edit')
        en
        let mytab = tabpagenr()
        let mybufnr = bufnr('')
        let args = s:ArgSplit(a:arg)
        let after = ''
        if get(args, 0) =~# '^+'
            let after = '|' . remove(args, 0)[1:-1]
        en
        try
            let file = len(args) ? s:Generate(s:Expand(join(args, ' '))) : fugitive#Real(@%)
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        if empty(file)
            return 'echoerr '.string('fugitive: cannot determine file path')
        en
        if file =~# '^fugitive:'
            return 'write' . (a:bang ? '! ' : ' ') . s:fnameescape(file)
        en
        exe s:DirCheck()
        let always_permitted = s:cpath(fugitive#Real(@%), file) && empty(s:DirCommitFile(@%)[1])
        if !always_permitted && !a:bang && (len(s:TreeChomp('diff', '--name-status', 'HEAD', '--', file)) || len(s:TreeChomp('ls-files', '--others', '--', file)))
            let v:errmsg = 'fugitive: file has uncommitted changes (use ! to override)'
            return 'echoerr v:errmsg'
        en
        let treebufnr = 0
        for nr in range(1,bufnr('$'))
            if fnamemodify(bufname(nr),':p') ==# file
                let treebufnr = nr
            en
        endfor

        if treebufnr > 0 && treebufnr != bufnr('')
            let temp = tempname()
            silent execute 'keepalt %write '.temp
            for tab in [mytab] + range(1,tabpagenr('$'))
                for winnr in range(1,tabpagewinnr(tab,'$'))
                    if tabpagebuflist(tab)[winnr-1] == treebufnr
                        exe  'tabnext '.tab
                        if winnr != winnr()
                            exe  winnr.'wincmd w'
                            let restorewinnr = 1
                        en
                        try
                            let lnum = line('.')
                            let last = line('$')
                            silent execute '$read '.temp
                            silent execute '1,'.last.'delete_'
                            silent write!
                            silent execute lnum
                            diffupdate
                            let did = 1
                        finally
                            if exists('restorewinnr')
                                wincmd p
                            en
                            exe  'tabnext '.mytab
                        endtry
                        break
                    en
                endfor
            endfor
            if !exists('did')
                call writefile(readfile(temp,'b'),file,'b')
            en
        el
            exe  'write! '.s:fnameescape(file)
        en

        let message = s:ChompStderr(['add'] + (a:bang ? ['--force'] : []) + ['--', file])
        if len(message)
            let v:errmsg = 'fugitive: '.message
            return 'echoerr v:errmsg'
        en
        if s:cpath(fugitive#Real(@%), file) && s:DirCommitFile(@%)[1] =~# '^\d$'
            setl  nomodified
        en

        let one = fugitive#Find(':1:'.file)
        let two = fugitive#Find(':2:'.file)
        let three = fugitive#Find(':3:'.file)
        for nr in range(1,bufnr('$'))
            let name = fnamemodify(bufname(nr), ':p')
            if bufloaded(nr) && !getbufvar(nr,'&modified') && (name ==# one || name ==# two || name ==# three)
                exe  nr.'bdelete'
            en
        endfor

        unlet! restorewinnr
        let zero = fugitive#Find(':0:'.file)
        exe s:DoAutocmd('BufWritePost ' . s:fnameescape(zero))
        for tab in range(1,tabpagenr('$'))
            for winnr in range(1,tabpagewinnr(tab,'$'))
                let bufnr = tabpagebuflist(tab)[winnr-1]
                let bufname = fnamemodify(bufname(bufnr), ':p')
                if bufname ==# zero && bufnr != mybufnr
                    exe  'tabnext '.tab
                    if winnr != winnr()
                        exe  winnr.'wincmd w'
                        let restorewinnr = 1
                    en
                    try
                        let lnum = line('.')
                        let last = line('$')
                        silent execute '$read '.s:fnameescape(file)
                        silent execute '1,'.last.'delete_'
                        silent execute lnum
                        setl  nomodified
                        diffupdate
                    finally
                        if exists('restorewinnr')
                            wincmd p
                        en
                        exe  'tabnext '.mytab
                    endtry
                    break
                en
            endfor
        endfor
        call fugitive#DidChange()
        return 'checktime' . after
    endf

    fun! fugitive#WqCommand(...) abort
        let bang = a:4 ? '!' : ''
        if s:cpath(expand('%:p'), fugitive#Find('.git/COMMIT_EDITMSG'))
            return 'wq'.bang
        en
        let result = call('fugitive#WriteCommand', a:000)
        if result =~# '^\%(write\|wq\|echoerr\)'
            return s:sub(result,'^write','wq')
        el
            return result.'|quit'.bang
        en
    endf

" Section: :Git push, :Git fetch

    fun! s:CompletePush(A, L, P, ...) abort
        let dir = a:0 ? a:1 : s:Dir()
        let remote = matchstr(a:L, '\u\w*[! ] *.\{-\}\s\@<=\zs[^-[:space:]]\S*\ze ')
        if empty(remote)
            let matches = s:LinesError([dir, 'remote'])[0]
        elseif a:A =~# ':'
            let lead = matchstr(a:A, '^[^:]*:')
            let matches = s:LinesError([dir, 'ls-remote', remote])[0]
            call filter(matches, 'v:val =~# "\t" && v:val !~# "{"')
            call map(matches, 'lead . s:sub(v:val, "^.*\t", "")')
        el
            let matches = s:CompleteHeads(dir)
            if a:A =~# '^[\''"]\=+'
                call map(matches, '"+" . v:val')
            en
        en
        return s:FilterEscape(matches, a:A)
    endf

    fun! fugitive#PushComplete(A, L, P, ...) abort
        return s:CompleteSub('push', a:A, a:L, a:P, function('s:CompletePush'), a:000)
    endf

    fun! fugitive#FetchComplete(A, L, P, ...) abort
        return s:CompleteSub('fetch', a:A, a:L, a:P, function('s:CompleteRemote'), a:000)
    endf

    fun! s:PushSubcommand(...) abort
        return {'no_more': 1}
    endf

    fun! s:FetchSubcommand(...) abort
        return {'no_more': 1}
    endf

" Section: :Gdiff

    aug  fugitive_diff
        au!
        au BufWinLeave * nested
                    \ if s:can_diffoff(+expand('<abuf>')) && s:diff_window_count() == 2 |
                    \   call s:diffoff_all(s:Dir(+expand('<abuf>'))) |
                    \ endif
        au BufWinEnter * nested
                    \ if s:can_diffoff(+expand('<abuf>')) && s:diff_window_count() == 1 |
                    \   call s:diffoff() |
                    \ endif
    aug  END

    fun! s:can_diffoff(buf) abort
        return getwinvar(bufwinnr(a:buf), '&diff') &&
                    \ !empty(getwinvar(bufwinnr(a:buf), 'fugitive_diff_restore'))
    endf

    fun! fugitive#CanDiffoff(buf) abort
        return s:can_diffoff(bufnr(a:buf))
    endf

    fun! s:DiffModifier(count, default) abort
        let fdc = matchstr(&diffopt, 'foldcolumn:\zs\d\+')
        if &diffopt =~# 'horizontal' && &diffopt !~# 'vertical'
            return ''
        elseif &diffopt =~# 'vertical'
            return 'vertical '
        elseif !get(g:, 'fugitive_diffsplit_directional_fit', a:default)
            return ''
        elseif winwidth(0) <= a:count * ((&tw ? &tw : 80) + (empty(fdc) ? 2 : fdc))
            return ''
        el
            return 'vertical '
        en
    endf

    fun! s:diff_window_count() abort
        let c = 0
        for nr in range(1,winnr('$'))
            let c += getwinvar(nr,'&diff')
        endfor
        return c
    endf

    fun! s:diff_restore() abort
        let restore = 'setl  nodiff noscrollbind'
                    \ . ' scrollopt=' . &l:scrollopt
                    \ . (&l:wrap ? ' wrap' : ' nowrap')
                    \ . ' foldlevel=999'
                    \ . ' foldmethod=' . &l:foldmethod
                    \ . ' foldcolumn=' . &l:foldcolumn
                    \ . ' foldlevel=' . &l:foldlevel
                    \ . (&l:foldenable ? ' foldenable' : ' nofoldenable')
        if has('cursorbind')
            let restore .= (&l:cursorbind ? ' ' : ' no') . 'cursorbind'
        en
        return restore
    endf

    fun! s:diffthis() abort
        if !&diff
            let w:fugitive_diff_restore = s:diff_restore()
            diffthis
        en
    endf

    fun! s:diffoff() abort
        if exists('w:fugitive_diff_restore') && v:version < 704
            exe  w:fugitive_diff_restore
        en
        unlet! w:fugitive_diff_restore
        diffoff
    endf

    fun! s:diffoff_all(dir) abort
        let curwin = winnr()
        for nr in range(1,winnr('$'))
            if getwinvar(nr, '&diff') && !empty(getwinvar(nr, 'fugitive_diff_restore'))
                if v:version < 704
                    if nr != winnr()
                        exe  nr.'wincmd w'
                    en
                    exe  w:fugitive_diff_restore
                en
                call setwinvar(nr, 'fugitive_diff_restore', '')
            en
        endfor
        if curwin != winnr()
            exe  curwin.'wincmd w'
        en
        diffoff!
    endf

    fun! s:IsConflicted() abort
        return len(@%) && !empty(s:ChompDefault('', ['ls-files', '--unmerged', '--', expand('%:p')]))
    endf

    fun! fugitive#Diffsplit(autodir, keepfocus, mods, arg, ...) abort
        exe s:VersionCheck()
        let args = s:ArgSplit(a:arg)
        let post = ''
        let autodir = a:autodir
        while get(args, 0, '') =~# '^++'
            if args[0] =~? '^++novertical$'
                let autodir = 0
            el
                return 'echoerr ' . string('fugitive: unknown option ' . args[0])
            en
            call remove(args, 0)
        endwhile
        if get(args, 0) =~# '^+'
            let post = remove(args, 0)[1:-1]
        en
        if exists(':DiffGitCached') && empty(args)
            return s:Mods(a:mods) . 'DiffGitCached' . (len(post) ? '|' . post : '')
        en
        let commit = s:DirCommitFile(@%)[1]
        if a:mods =~# '\<tab\>'
            let mods = substitute(a:mods, '\<tab\>', '', 'g')
            let pre = 'tab split'
        el
            let mods = 'keepalt ' . a:mods
            let pre = ''
        en
        let back = exists('*win_getid') ? 'call win_gotoid(' . win_getid() . ')' : 'wincmd p'
        if (empty(args) || args[0] =~# '^>\=:$') && a:keepfocus
            exe s:DirCheck()
            if commit =~# '^1\=$' && s:IsConflicted()
                let parents = [s:Relative(':2:'), s:Relative(':3:')]
            elseif empty(commit)
                let parents = [s:Relative(':0:')]
            elseif commit =~# '^\d\=$'
                let parents = [s:Relative('@:')]
            elseif commit =~# '^\x\x\+$'
                let parents = s:LinesError(['rev-parse', commit . '^@'])[0]
                call map(parents, 's:Relative(v:val . ":")')
            en
        en
        try
            if exists('parents') && len(parents) > 1
                exe pre
                let mods = (autodir ? s:DiffModifier(len(parents) + 1, empty(args) || args[0] =~# '^>') : '') . s:Mods(mods, 'leftabove')
                let nr = bufnr('')
                if len(parents) > 1 && !&equalalways
                    let equalalways = 0
                    set equalalways
                en
                exe  mods 'split' s:fnameescape(fugitive#Find(parents[0]))
                call s:Map('n', 'dp', ':diffput '.nr.'<Bar>diffupdate<CR>', '<silent>')
                let nr2 = bufnr('')
                call s:diffthis()
                exe back
                call s:Map('n', 'd2o', ':diffget '.nr2.'<Bar>diffupdate<CR>', '<silent>')
                let mods = substitute(mods, '\Cleftabove\|rightbelow\|aboveleft\|belowright', '\=submatch(0) =~# "f" ? "rightbelow" : "leftabove"', '')
                for i in range(len(parents)-1, 1, -1)
                    exe  mods 'split' s:fnameescape(fugitive#Find(parents[i]))
                    call s:Map('n', 'dp', ':diffput '.nr.'<Bar>diffupdate<CR>', '<silent>')
                    let nrx = bufnr('')
                    call s:diffthis()
                    exe back
                    call s:Map('n', 'd' . (i + 2) . 'o', ':diffget '.nrx.'<Bar>diffupdate<CR>', '<silent>')
                endfor
                call s:diffthis()
                return post
            elseif len(args)
                let arg = join(args, ' ')
                if arg ==# ''
                    return post
                elseif arg ==# ':/'
                    exe s:DirCheck()
                    let file = s:Relative()
                elseif arg ==# ':'
                    exe s:DirCheck()
                    let file = len(commit) ? s:Relative() : s:Relative(s:IsConflicted() ? ':1:' : ':0:')
                elseif arg =~# '^:\d$'
                    exe s:DirCheck()
                    let file = s:Relative(arg . ':')
                elseif arg =~# '^[~^]\d*$'
                    return 'echoerr ' . string('fugitive: change ' . arg . ' to !' . arg . ' to diff against ancestor')
                el
                    try
                        let file = arg =~# '^:/.' ? fugitive#RevParse(arg) . s:Relative(':') : s:Expand(arg)
                    catch /^fugitive:/
                        return 'echoerr ' . string(v:exception)
                    endtry
                en
                if a:keepfocus || arg =~# '^>'
                    let mods = s:Mods(a:mods, 'leftabove')
                el
                    let mods = s:Mods(a:mods)
                en
            elseif exists('parents')
                let file = get(parents, -1, s:Relative(repeat('0', 40). ':'))
                let mods = s:Mods(a:mods, 'leftabove')
            elseif len(commit)
                let file = s:Relative()
                let mods = s:Mods(a:mods, 'rightbelow')
            elseif s:IsConflicted()
                let file = s:Relative(':1:')
                let mods = s:Mods(a:mods, 'leftabove')
                if get(g:, 'fugitive_legacy_commands', 1)
                    let post = 'echohl WarningMsg|echo "Use :Gdiffsplit! for 3 way diff"|echohl NONE|' . post
                en
            el
                exe s:DirCheck()
                let file = s:Relative(':0:')
                let mods = s:Mods(a:mods, 'leftabove')
            en
            let spec = s:Generate(file)
            if spec =~# '^fugitive:' && empty(s:DirCommitFile(spec)[2])
                let spec = FugitiveVimPath(spec . s:Relative('/'))
            en
            exe pre
            let restore = s:diff_restore()
            let w:fugitive_diff_restore = restore
            let mods = (autodir ? s:DiffModifier(2, empty(args) || args[0] =~# '^>') : '') . mods
            if &diffopt =~# 'vertical'
                let diffopt = &diffopt
                set diffopt-=vertical
            en
            exe  mods 'diffsplit' s:fnameescape(spec)
            let w:fugitive_diff_restore = restore
            let winnr = winnr()
            if getwinvar('#', '&diff')
                if a:keepfocus
                    exe back
                en
            en
            return post
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        finally
            if exists('l:equalalways')
                let &g:equalalways = equalalways
            en
            if exists('diffopt')
                let &diffopt = diffopt
            en
        endtry
    endf

" Section: :GMove, :GRemove

    fun! s:Move(force, rename, destination) abort
        let dir = s:Dir()
        exe s:DirCheck(dir)
        if s:DirCommitFile(@%)[1] !~# '^0\=$' || empty(@%)
            return 'echoerr ' . string('fugitive: mv not supported for this buffer')
        en
        if a:rename
            let default_root = expand('%:p:s?[\/]$??:h') . '/'
        el
            let default_root = s:Tree(dir) . '/'
        en
        if a:destination =~# '^:/:\='
            let destination = s:Tree(dir) . s:Expand(substitute(a:destination, '^:/:\=', '', ''))
        elseif a:destination =~# '^:(top)'
            let destination = s:Expand(matchstr(a:destination, ')\zs.*'))
            if destination !~# '^/\|^\a\+:'
                let destination = s:Tree(dir) . '/' . destination
            en
            let destination = s:Tree(dir) .
        elseif a:destination =~# '^:(\%(top,literal\|literal,top\))'
            let destination = s:Tree(dir) . matchstr(a:destination, ')\zs.*')
        elseif a:destination =~# '^:(literal)\.\.\=\%(/\|$\)'
            let destination = simplify(getcwd() . '/' . matchstr(a:destination, ')\zs.*'))
        elseif a:destination =~# '^:(literal)'
            let destination = simplify(default_root . matchstr(a:destination, ')\zs.*'))
        el
            let destination = s:Expand(a:destination)
            if destination =~# '^\.\.\=\%(/\|$\)'
                let destination = simplify(getcwd() . '/' . destination)
            elseif destination !~# '^\a\+:\|^/'
                let destination = default_root . destination
            en
        en
        let destination = s:Slash(destination)
        if isdirectory(@%)
            setl  noswapfile
        en
        let exec = fugitive#Execute(['mv'] + (a:force ? ['-f'] : []) + ['--', expand('%:p'), destination], dir)
        if exec.exit_status && exec.stderr !=# ['']
            return 'echoerr ' .string('fugitive: '.s:JoinChomp(exec.stderr))
        en
        if isdirectory(destination)
            let destination = fnamemodify(s:sub(destination,'/$','').'/'.expand('%:t'),':.')
        en
        let reload = '|call fugitive#DidChange(' . string(exec) . ')'
        if empty(s:DirCommitFile(@%)[1])
            if isdirectory(destination)
                return 'keepalt edit '.s:fnameescape(destination) . reload
            el
                return 'keepalt saveas! '.s:fnameescape(destination) . reload
            en
        el
            return 'file '.s:fnameescape(fugitive#Find(':0:'.destination, dir)) . reload
        en
    endf

    fun! fugitive#RenameComplete(A,L,P) abort
        if a:A =~# '^[.:]\=/'
            return fugitive#CompletePath(a:A)
        el
            let pre = s:Slash(fnamemodify(expand('%:p:s?[\/]$??'), ':h')) . '/'
            return map(fugitive#CompletePath(pre.a:A), 'strpart(v:val, len(pre))')
        en
    endf

    fun! fugitive#MoveCommand(line1, line2, range, bang, mods, arg, ...) abort
        return s:Move(a:bang, 0, a:arg)
    endf

    fun! fugitive#RenameCommand(line1, line2, range, bang, mods, arg, ...) abort
        return s:Move(a:bang, 1, a:arg)
    endf

    fun! s:Remove(after, force) abort
        let dir = s:Dir()
        exe s:DirCheck(dir)
        if len(@%) && s:DirCommitFile(@%)[1] ==# ''
            let cmd = ['rm']
        elseif s:DirCommitFile(@%)[1] ==# '0'
            let cmd = ['rm','--cached']
        el
            return 'echoerr ' . string('fugitive: rm not supported for this buffer')
        en
        if a:force
            let cmd += ['--force']
        en
        let message = s:ChompStderr(cmd + ['--', expand('%:p')], dir)
        if len(message)
            let v:errmsg = 'fugitive: '.s:sub(message,'error:.*\zs\n\(.*-f.*',' (add ! to force)')
            return 'echoerr '.string(v:errmsg)
        el
            return a:after . (a:force ? '!' : ''). '|call fugitive#DidChange(' . string(dir) . ')'
        en
    endf

    fun! fugitive#RemoveCommand(line1, line2, range, bang, mods, arg, ...) abort
        return s:Remove('edit', a:bang)
    endf

    fun! fugitive#UnlinkCommand(line1, line2, range, bang, mods, arg, ...) abort
        return s:Remove('edit', a:bang)
    endf

    fun! fugitive#DeleteCommand(line1, line2, range, bang, mods, arg, ...) abort
        return s:Remove('bdelete', a:bang)
    endf

" Section: :Git blame

    fun! s:Keywordprg() abort
        let args = ' --git-dir='.escape(s:Dir(),"\\\"' ")
        if has('gui_running') && !has('win32')
            return s:GitShellCmd() . ' --no-pager' . args . ' log -1'
        el
            return s:GitShellCmd() . args . ' show'
        en
    endf

    fun! s:linechars(pattern) abort
        let chars = strlen(s:gsub(matchstr(getline('.'), a:pattern), '.', '.'))
        if exists('*synconcealed') && &conceallevel > 1
            for col in range(1, chars)
                let chars -= synconcealed(line('.'), col)[0]
            endfor
        en
        return chars
    endf

    fun! s:BlameBufnr(...) abort
        let state = s:TempState(a:0 ? a:1 : bufnr(''))
        if get(state, 'filetype', '') ==# 'fugitiveblame'
            return get(state, 'origin_bufnr', -1)
        el
            return -1
        en
    endf

    fun! s:BlameCommitFileLnum(...) abort
        let line = a:0 ? a:1 : getline('.')
        let state = a:0 > 1 ? a:2 : s:TempState()
        if get(state, 'filetype', '') !=# 'fugitiveblame'
            return ['', '', 0]
        en
        let commit = matchstr(line, '^\^\=[?*]*\zs\x\+')
        if commit =~# '^0\+$'
            let commit = ''
        elseif has_key(state, 'blame_reverse_end')
            let commit = get(s:LinesError([state.git_dir, 'rev-list', '--ancestry-path', '--reverse', commit . '..' . state.blame_reverse_end])[0], 0, '')
        en
        let lnum = +matchstr(line, ' \zs\d\+\ze \%((\| *\d\+)\)')
        let path = matchstr(line, '^\^\=[?*]*\x* \+\%(\d\+ \+\d\+ \+\)\=\zs.\{-\}\ze\s*\d\+ \%((\| *\d\+)\)')
        if empty(path) && lnum
            let path = get(state, 'blame_file', '')
        en
        return [commit, path, lnum]
    endf

    fun! s:BlameLeave() abort
        let bufwinnr = bufwinnr(s:BlameBufnr())
        if bufwinnr > 0
            let bufnr = bufnr('')
            exe bufwinnr . 'wincmd w'
            return bufnr . 'bdelete'
        en
        return ''
    endf

    fun! s:BlameQuit() abort
        let cmd = s:BlameLeave()
        if empty(cmd)
            return 'bdelete'
        elseif len(s:DirCommitFile(@%)[1])
            return cmd . '|Gedit'
        el
            return cmd
        en
    endf

    fun! fugitive#BlameComplete(A, L, P) abort
        return s:CompleteSub('blame', a:A, a:L, a:P)
    endf

    fun! s:BlameSubcommand(line1, count, range, bang, mods, options) abort
        let dir = s:Dir(a:options)
        exe s:DirCheck(dir)
        let flags = copy(a:options.subcommand_args)
        let i = 0
        let raw = 0
        let commits = []
        let files = []
        let ranges = []
        if a:line1 > 0 && a:count > 0 && a:range != 1
            call extend(ranges, ['-L', a:line1 . ',' . a:count])
        en
        while i < len(flags)
            let match = matchlist(flags[i], '^\(-[a-zABDFH-KN-RT-Z]\)\ze\(.*\)')
            if len(match) && len(match[2])
                call insert(flags, match[1])
                let flags[i+1] = '-' . match[2]
                continue
            en
            let arg = flags[i]
            if arg =~# '^-p$\|^--\%(help\|porcelain\|line-porcelain\|incremental\)$'
                let raw = 1
            elseif arg ==# '--contents' && i + 1 < len(flags)
                call extend(commits, remove(flags, i, i+1))
                continue
            elseif arg ==# '-L' && i + 1 < len(flags)
                call extend(ranges, remove(flags, i, i+1))
                continue
            elseif arg =~# '^--contents='
                call add(commits, remove(flags, i))
                continue
            elseif arg =~# '^-L.'
                call add(ranges, remove(flags, i))
                continue
            elseif arg =~# '^-[GLS]$\|^--\%(date\|encoding\|contents\|ignore-rev\|ignore-revs-file\)$'
                let i += 1
                if i == len(flags)
                    echohl ErrorMsg
                    echo s:ChompStderr([dir, 'blame', arg])
                    echohl NONE
                    return ''
                en
            elseif arg ==# '--'
                if i + 1 < len(flags)
                    call extend(files, remove(flags, i + 1, -1))
                en
                call remove(flags, i)
                break
            elseif arg !~# '^-' && (s:HasOpt(flags, '--not') || arg !~# '^\^')
                if index(flags, '--') >= 0
                    call add(commits, remove(flags, i))
                    continue
                en
                if arg =~# '\.\.' && arg !~# '^\.\.\=\%(/\|$\)' && empty(commits)
                    call add(commits, remove(flags, i))
                    continue
                en
                try
                    let dcf = s:DirCommitFile(fugitive#Find(arg, dir))
                    if len(dcf[1]) && empty(dcf[2])
                        call add(commits, remove(flags, i))
                        continue
                    en
                catch /^fugitive:/
                endtry
                call add(files, remove(flags, i))
                continue
            en
            let i += 1
        endwhile
        let file = substitute(get(files, 0, get(s:TempState(), 'blame_file', s:Relative('./', dir))), '^\.\%(/\|$\)', '', '')
        if empty(commits) && len(files) > 1
            call add(commits, remove(files, 1))
        en
        exe s:BlameLeave()
        try
            let cmd = a:options.flags + ['--no-pager', '-c', 'blame.coloring=none', '-c', 'blame.blankBoundary=false', a:options.subcommand, '--show-number']
            call extend(cmd, filter(copy(flags), 'v:val !~# "\\v^%(-b|--%(no-)=color-.*|--progress)$"'))
            if a:count > 0 && empty(ranges)
                let cmd += ['-L', (a:line1 ? a:line1 : line('.')) . ',' . (a:line1 ? a:line1 : line('.'))]
            en
            call extend(cmd, ranges)
            let tempname = tempname()
            let temp = tempname . (raw ? '' : '.fugitiveblame')
            if len(commits)
                let cmd += commits
            elseif empty(files) && len(matchstr(s:DirCommitFile(@%)[1], '^\x\x\+$'))
                let cmd += [matchstr(s:DirCommitFile(@%)[1], '^\x\x\+$')]
            elseif empty(files) && !s:HasOpt(flags, '--reverse')
                if &modified || !empty(s:DirCommitFile(@%)[1])
                    let cmd += ['--contents', tempname . '.in']
                    silent execute 'noautocmd keepalt %write ' . s:fnameescape(tempname . '.in')
                    let delete_in = 1
                elseif &autoread
                    exe 'checktime ' . bufnr('')
                en
            el
                call fugitive#Autowrite()
            en
            let basecmd = [{'git': a:options.git, 'git_dir': dir}] + ['--literal-pathspecs'] + cmd + ['--'] + (len(files) ? files : [file])
            let [err, exec_error] = s:StdoutToFile(temp, basecmd)
            if exists('delete_in')
                call delete(tempname . '.in')
            en
            redraw
            try
                if exec_error
                    let lines = split(err, "\n")
                    if empty(lines)
                        let lines = readfile(temp)
                    en
                    for i in range(len(lines))
                        if lines[i] =~# '^error: \|^fatal: '
                            echohl ErrorMsg
                            echon lines[i]
                            echohl NONE
                            break
                        el
                            echon lines[i]
                        en
                        if i != len(lines) - 1
                            echon "\n"
                        en
                    endfor
                    return ''
                en
                let temp_state = {
                            \ 'git': a:options.git,
                            \ 'flags': a:options.flags,
                            \ 'args': [a:options.subcommand] + a:options.subcommand_args,
                            \ 'dir': dir,
                            \ 'git_dir': dir,
                            \ 'cwd': s:UserCommandCwd(dir),
                            \ 'filetype': (raw ? 'git' : 'fugitiveblame'),
                            \ 'blame_options': a:options,
                            \ 'blame_flags': flags,
                            \ 'blame_file': file}
                if s:HasOpt(flags, '--reverse')
                    let temp_state.blame_reverse_end = matchstr(get(commits, 0, ''), '\.\.\zs.*')
                en
                if a:line1 == 0 && a:count == 1
                    if get(a:options, 'curwin')
                        let edit = 'edit'
                    elseif a:bang
                        let edit = 'pedit'
                    el
                        let edit = 'split'
                    en
                    return s:BlameCommit(s:Mods(a:mods) . edit, get(readfile(temp), 0, ''), temp_state)
                elseif (a:line1 == 0 || a:range == 1) && a:count > 0
                    let edit = s:Mods(a:mods) . get(['edit', 'split', 'pedit', 'vsplit', 'tabedit', 'edit'], a:count - (a:line1 ? a:line1 : 1), 'split')
                    return s:BlameCommit(edit, get(readfile(temp), 0, ''), temp_state)
                el
                    let temp = s:Resolve(temp)
                    let temp_state.file = temp
                    call s:RunSave(temp_state)
                    if len(ranges + commits + files) || raw
                        let reload = '|call fugitive#DidChange(fugitive#Result(' . string(temp_state.file) . '))'
                        let mods = s:Mods(a:mods)
                        if a:count != 0
                            exe 'silent keepalt' mods get(a:options, 'curwin') ? 'edit' : 'split' s:fnameescape(temp)
                        elseif !&modified || a:bang || &bufhidden ==# 'hide' || (empty(&bufhidden) && &hidden)
                            exe 'silent' mods 'edit' . (a:bang ? '! ' : ' ') . s:fnameescape(temp)
                        el
                            return mods . 'edit ' . s:fnameescape(temp) . reload
                        en
                        return reload[1 : -1]
                    en
                    if a:mods =~# '\<tab\>'
                        silent tabedit %
                    en
                    let bufnr = bufnr('')
                    let temp_state.origin_bufnr = bufnr
                    let restore = []
                    let mods = substitute(a:mods, '\<tab\>', '', 'g')
                    for winnr in range(winnr('$'),1,-1)
                        if getwinvar(winnr, '&scrollbind')
                            if !&l:scrollbind
                                call setwinvar(winnr, '&scrollbind', 0)
                            elseif winnr != winnr() && getwinvar(winnr, '&foldenable')
                                call setwinvar(winnr, '&foldenable', 0)
                                call add(restore, 'call setwinvar(bufwinnr('.winbufnr(winnr).'),"&foldenable",1)')
                            en
                        en
                        let win_blame_bufnr = s:BlameBufnr(winbufnr(winnr))
                        if getwinvar(winnr, '&scrollbind') ? win_blame_bufnr == bufnr : win_blame_bufnr > 0
                            exe  winbufnr(winnr).'bdelete'
                        en
                    endfor
                    let restore_winnr = 'bufwinnr(' . bufnr . ')'
                    if !&l:scrollbind
                        call add(restore, 'call setwinvar(' . restore_winnr . ',"&scrollbind",0)')
                    en
                    if &l:wrap
                        call add(restore, 'call setwinvar(' . restore_winnr . ',"&wrap",1)')
                    en
                    if &l:foldenable
                        call add(restore, 'call setwinvar(' . restore_winnr . ',"&foldenable",1)')
                    en
                    setl  scrollbind nowrap nofoldenable
                    let top = line('w0') + &scrolloff
                    let current = line('.')
                    exe 'silent keepalt' (a:bang ? s:Mods(mods) . 'split' : s:Mods(mods, 'leftabove') . 'vsplit') s:fnameescape(temp)
                    let w:fugitive_leave = join(restore, '|')
                    exe  top
                    norm! zt
                    exe  current
                    setl  nonumber scrollbind nowrap foldcolumn=0 nofoldenable winfixwidth
                    if exists('+relativenumber')
                        setl  norelativenumber
                    en
                    if exists('+signcolumn')
                        setl  signcolumn=no
                    en
                    exe  "vertical resize ".(s:linechars('.\{-\}\s\+\d\+\ze)')+1)
                    redraw
                    syncbind
                    exe s:DoAutocmdChanged(temp_state)
                en
            endtry
            return ''
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
    endf

    fun! s:BlameCommit(cmd, ...) abort
        let line = a:0 ? a:1 : getline('.')
        let state = a:0 ? a:2 : s:TempState()
        let sigil = has_key(state, 'blame_reverse_end') ? '-' : '+'
        let mods = (s:BlameBufnr() < 0 ? '' : &splitbelow ? "botright " : "topleft ")
        let [commit, path, lnum] = s:BlameCommitFileLnum(line, state)
        if empty(commit) && len(path) && has_key(state, 'blame_reverse_end')
            let path = (len(state.blame_reverse_end) ? state.blame_reverse_end . ':' : ':(top)') . path
            return fugitive#Open(mods . a:cmd, 0, '', '+' . lnum . ' ' . s:fnameescape(path), ['+' . lnum, path])
        en
        if commit =~# '^0*$'
            return 'echoerr ' . string('fugitive: no commit')
        en
        if line =~# '^\^' && !has_key(state, 'blame_reverse_end')
            let path = commit . ':' . path
            return fugitive#Open(mods . a:cmd, 0, '', '+' . lnum . ' ' . s:fnameescape(path), ['+' . lnum, path])
        en
        let cmd = fugitive#Open(mods . a:cmd, 0, '', commit, [commit])
        if cmd =~# '^echoerr'
            return cmd
        en
        exe  cmd
        if a:cmd ==# 'pedit' || empty(path)
            return ''
        en
        if search('^diff .* b/\M'.escape(path,'\').'$','W')
            call search('^+++')
            let head = line('.')
            while search('^@@ \|^diff ') && getline('.') =~# '^@@ '
                let top = +matchstr(getline('.'),' ' . sigil .'\zs\d\+')
                let len = +matchstr(getline('.'),' ' . sigil . '\d\+,\zs\d\+')
                if lnum >= top && lnum <= top + len
                    let offset = lnum - top
                    if &scrolloff
                        +
                        norm! zt
                    el
                        norm! zt
                        +
                    en
                    while offset > 0 && line('.') < line('$')
                        +
                        if getline('.') =~# '^[ ' . sigil . ']'
                            let offset -= 1
                        en
                    endwhile
                    return 'normal! zv'
                en
            endwhile
            exe  head
            norm! zt
        en
        return ''
    endf

    fun! s:BlameJump(suffix, ...) abort
        let suffix = a:suffix
        let [commit, path, lnum] = s:BlameCommitFileLnum()
        if empty(path)
            return 'echoerr ' . string('fugitive: could not determine filename for blame')
        en
        if commit =~# '^0*$'
            let commit = '@'
            let suffix = ''
        en
        let offset = line('.') - line('w0')
        let state = s:TempState()
        let flags = get(state, 'blame_flags', [])
        let blame_bufnr = s:BlameBufnr()
        if blame_bufnr > 0
            let bufnr = bufnr('')
            let winnr = bufwinnr(blame_bufnr)
            if winnr > 0
                exe winnr.'wincmd w'
                exe bufnr.'bdelete'
            en
            exe  'Gedit' s:fnameescape(commit . suffix . ':' . path)
            exe  lnum
        en
        let my_bufnr = bufnr('')
        if blame_bufnr < 0
            let blame_args = flags + [commit . suffix, '--', path]
            let result = s:BlameSubcommand(0, 0, 0, 0, '', extend({'subcommand_args': blame_args}, state.blame_options, 'keep'))
        el
            let blame_args = flags
            let result = s:BlameSubcommand(-1, -1, 0, 0, '', extend({'subcommand_args': blame_args}, state.blame_options, 'keep'))
        en
        if bufnr('') == my_bufnr
            return result
        en
        exe  result
        exe  lnum
        let delta = line('.') - line('w0') - offset
        if delta > 0
            exe  'normal! '.delta."\<C-E>"
        elseif delta < 0
            exe  'normal! '.(-delta)."\<C-Y>"
        en
        keepjumps syncbind
        redraw
        echo ':Git blame' s:fnameescape(blame_args)
        return ''
    endf

    let s:hash_colors = {}

    fun! fugitive#BlameSyntax() abort
        let conceal = has('conceal') ? ' conceal' : ''
        let flags = get(s:TempState(), 'blame_flags', [])
        syn spell notoplevel
        syn match FugitiveblameBlank                      "^\s\+\s\@=" nextgroup=FugitiveblameAnnotation,FugitiveblameScoreDebug,FugitiveblameOriginalFile,FugitiveblameOriginalLineNumber skipwhite
        syn match FugitiveblameHash       "\%(^\^\=[?*]*\)\@<=\<\x\{7,\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameScoreDebug,FugitiveblameOriginalLineNumber,FugitiveblameOriginalFile skipwhite
        if s:HasOpt(flags, '-b') || FugitiveConfigGet('blame.blankBoundary') =~# '^1$\|^true$'
            syn match FugitiveblameBoundaryIgnore "^\^[*?]*\x\{7,\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameScoreDebug,FugitiveblameOriginalLineNumber,FugitiveblameOriginalFile skipwhite
        el
            syn match FugitiveblameBoundary "^\^"
        en
        syn match FugitiveblameScoreDebug        " *\d\+\s\+\d\+\s\@=" nextgroup=FugitiveblameAnnotation,FugitiveblameOriginalLineNumber,fugitiveblameOriginalFile contained skipwhite
        syn region FugitiveblameAnnotation matchgroup=FugitiveblameDelimiter start="(" end="\%(\s\d\+\)\@<=)" contained keepend oneline
        syn match FugitiveblameTime "\<[0-9:/+-][0-9:/+ -]*[0-9:/+-]\%(\s\+\d\+)\)\@=" contained containedin=FugitiveblameAnnotation
        exec 'syn match FugitiveblameLineNumber         "\s[[:digit:][:space:]]\{0,' . (len(line('$'))-1). '\}\d)\@=" contained containedin=FugitiveblameAnnotation' conceal
        exec 'syn match FugitiveblameOriginalFile       "\s\%(\f\+\D\@<=\|\D\@=\f\+\)\%(\%(\s\+\d\+\)\=\s\%((\|\s*\d\+)\)\)\@=" contained nextgroup=FugitiveblameOriginalLineNumber,FugitiveblameAnnotation skipwhite' (s:HasOpt(flags, '--show-name', '-f') ? '' : conceal)
        exec 'syn match FugitiveblameOriginalLineNumber "\s*\d\+\%(\s(\)\@=" contained nextgroup=FugitiveblameAnnotation skipwhite' (s:HasOpt(flags, '--show-number', '-n') ? '' : conceal)
        exec 'syn match FugitiveblameOriginalLineNumber "\s*\d\+\%(\s\+\d\+)\)\@=" contained nextgroup=FugitiveblameShort skipwhite' (s:HasOpt(flags, '--show-number', '-n') ? '' : conceal)
        syn match FugitiveblameShort              " \d\+)" contained contains=FugitiveblameLineNumber
        syn match FugitiveblameNotCommittedYet "(\@<=Not Committed Yet\>" contained containedin=FugitiveblameAnnotation
        hi def link FugitiveblameBoundary           Keyword
        hi def link FugitiveblameHash               Identifier
        hi def link FugitiveblameBoundaryIgnore     Ignore
        hi def link FugitiveblameUncommitted        Ignore
        hi def link FugitiveblameScoreDebug         Debug
        hi def link FugitiveblameTime               PreProc
        hi def link FugitiveblameLineNumber         Number
        hi def link FugitiveblameOriginalFile       String
        hi def link FugitiveblameOriginalLineNumber Float
        hi def link FugitiveblameShort              FugitiveblameDelimiter
        hi def link FugitiveblameDelimiter          Delimiter
        hi def link FugitiveblameNotCommittedYet    Comment
        if !get(g:, 'fugitive_dynamic_colors', 1) && !s:HasOpt(flags, '--color-lines') || s:HasOpt(flags, '--no-color-lines')
            return
        en
        let seen = {}
        for lnum in range(1, line('$'))
            let orig_hash = matchstr(getline(lnum), '^\^\=[*?]*\zs\x\{6\}')
            let hash = orig_hash
            let hash = substitute(hash, '\(\x\)\x', '\=submatch(1).printf("%x", 15-str2nr(submatch(1),16))', 'g')
            let hash = substitute(hash, '\(\x\x\)', '\=printf("%02x", str2nr(submatch(1),16)*3/4+32)', 'g')
            if hash ==# '' || orig_hash ==# '000000' || has_key(seen, hash)
                continue
            en
            let seen[hash] = 1
            if &t_Co == 256
                let [s, r, g, b; __] = map(matchlist(orig_hash, '\(\x\)\x\(\x\)\x\(\x\)\x'), 'str2nr(v:val,16)')
                let color = 16 + (r + 1) / 3 * 36 + (g + 1) / 3 * 6 + (b + 1) / 3
                if color == 16
                    let color = 235
                elseif color == 231
                    let color = 255
                en
                let s:hash_colors[hash] = ' ctermfg='.color
            el
                let s:hash_colors[hash] = ''
            en
            let pattern = substitute(orig_hash, '^\(\x\)\x\(\x\)\x\(\x\)\x$', '\1\\x\2\\x\3\\x', '') . '*\>'
            exe 'syn match FugitiveblameHash'.hash.'       "\%(^\^\=[*?]*\)\@<='.pattern.'" nextgroup=FugitiveblameAnnotation,FugitiveblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite'
        endfor
        syn match FugitiveblameUncommitted "\%(^\^\=[?*]*\)\@<=\<0\{7,\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameScoreDebug,FugitiveblameOriginalLineNumber,FugitiveblameOriginalFile skipwhite
        call s:BlameRehighlight()
    endf

    fun! s:BlameRehighlight() abort
        for [hash, cterm] in items(s:hash_colors)
            if !empty(cterm) || has('gui_running') || has('termguicolors') && &termguicolors
                exe 'hi FugitiveblameHash'.hash.' guifg=#' . hash . cterm
            el
                exe 'hi link FugitiveblameHash'.hash.' Identifier'
            en
        endfor
    endf

    fun! s:BlameMaps(is_ftplugin) abort
        let ft = a:is_ftplugin
        call s:Map('n', '<F1>', ':help :Git_blame<CR>', '<silent>', ft)
        call s:Map('n', 'g?',   ':help :Git_blame<CR>', '<silent>', ft)
        call s:Map('n', 'gq',   ':exe <SID>BlameQuit()<CR>', '<silent>', ft)
        call s:Map('n', '<2-LeftMouse>', ':<C-U>exe <SID>BlameCommit("exe <SID>BlameLeave()<Bar>edit")<CR>', '<silent>', ft)
        call s:Map('n', '<CR>', ':<C-U>exe <SID>BlameCommit("exe <SID>BlameLeave()<Bar>edit")<CR>', '<silent>', ft)
        call s:Map('n', '-',    ':<C-U>exe <SID>BlameJump("")<CR>', '<silent>', ft)
        call s:Map('n', 's',    ':<C-U>exe <SID>BlameJump("")<CR>', '<silent>', ft)
        call s:Map('n', 'u',    ':<C-U>exe <SID>BlameJump("")<CR>', '<silent>', ft)
        call s:Map('n', 'P',    ':<C-U>exe <SID>BlameJump("^".v:count1)<CR>', '<silent>', ft)
        call s:Map('n', '~',    ':<C-U>exe <SID>BlameJump("~".v:count1)<CR>', '<silent>', ft)
        call s:Map('n', 'i',    ':<C-U>exe <SID>BlameCommit("exe <SID>BlameLeave()<Bar>edit")<CR>', '<silent>', ft)
        call s:Map('n', 'o',    ':<C-U>exe <SID>BlameCommit("split")<CR>', '<silent>', ft)
        call s:Map('n', 'O',    ':<C-U>exe <SID>BlameCommit("tabedit")<CR>', '<silent>', ft)
        call s:Map('n', 'p',    ':<C-U>exe <SID>BlameCommit("pedit")<CR>', '<silent>', ft)
        call s:Map('n', '.',    ":<C-U> <C-R>=substitute(<SID>BlameCommitFileLnum()[0],'^$','@','')<CR><Home>", ft)
        call s:Map('n', '(',    "-", ft)
        call s:Map('n', ')',    "+", ft)
        call s:Map('n', 'A',    ":<C-u>exe 'vertical resize '.(<SID>linechars('.\\{-\\}\\ze [0-9:/+-][0-9:/+ -]* \\d\\+)')+1+v:count)<CR>", '<silent>', ft)
        call s:Map('n', 'C',    ":<C-u>exe 'vertical resize '.(<SID>linechars('^\\S\\+')+1+v:count)<CR>", '<silent>', ft)
        call s:Map('n', 'D',    ":<C-u>exe 'vertical resize '.(<SID>linechars('.\\{-\\}\\ze\\d\\ze\\s\\+\\d\\+)')+1-v:count)<CR>", '<silent>', ft)
    endf

    fun! fugitive#BlameFileType() abort
        setl  nomodeline
        setl  foldmethod=manual
        if len(s:Dir())
            let &l:keywordprg = s:Keywordprg()
        en
        let b:undo_ftplugin = 'setl keywordprg= foldmethod<'
        if exists('+concealcursor')
            setl  concealcursor=nc conceallevel=2
            let b:undo_ftplugin .= ' concealcursor< conceallevel<'
        en
        if &modifiable
            return ''
        en
        call s:BlameMaps(1)
    endf

    fun! s:BlameCursorSync(bufnr, line) abort
        if a:line == line('.')
            return
        en
        if get(s:TempState(), 'origin_bufnr') == a:bufnr || get(s:TempState(a:bufnr), 'origin_bufnr') == bufnr('')
            if &startofline
                exe  a:line
            el
                let pos = getpos('.')
                let pos[1] = a:line
                call setpos('.', pos)
            en
        en
    endf

    aug  fugitive_blame
        au!
        au ColorScheme,GUIEnter * call s:BlameRehighlight()
        au BufWinLeave * execute getwinvar(+bufwinnr(+expand('<abuf>')), 'fugitive_leave')
        au WinLeave * let s:cursor_for_blame = [bufnr(''), line('.')]
        au WinEnter * if exists('s:cursor_for_blame') | call call('s:BlameCursorSync', s:cursor_for_blame) | endif
    aug  END

" Section: :GBrowse

    fun! s:BrowserOpen(url, mods, echo_copy) abort
        let url = substitute(a:url, '[ <>\|"]', '\="%".printf("%02X",char2nr(submatch(0)))', 'g')
        let mods = s:Mods(a:mods)
        if a:echo_copy
            if has('clipboard')
                let @+ = url
            en
            return 'echo '.string(url)
        elseif exists(':Browse') == 2
            return 'echo '.string(url).'|' . mods . 'Browse '.url
        elseif exists(':OpenBrowser') == 2
            return 'echo '.string(url).'|' . mods . 'OpenBrowser '.url
        el
            if !exists('g:loaded_netrw')
                runtime! autoload/netrw.vim
            en
            if exists('*netrw#BrowseX')
                return 'echo '.string(url).'|' . mods . 'call netrw#BrowseX('.string(url).', 0)'
            elseif exists('*netrw#NetrwBrowseX')
                return 'echo '.string(url).'|' . mods . 'call netrw#NetrwBrowseX('.string(url).', 0)'
            el
                return 'echoerr ' . string('Netrw not found. Define your own :Browse to use :GBrowse')
            en
        en
    endf

    fun! fugitive#BrowseCommand(line1, count, range, bang, mods, arg, ...) abort
        exe s:VersionCheck()
        let dir = s:Dir()
        try
            let arg = a:arg
            if arg =~# '^++\%([Gg]it\)\=[Rr]emote='
                let remote = matchstr(arg, '^++\%([Gg]it\)\=[Rr]emote=\zs\S\+')
                let arg = matchstr(arg, '\s\zs\S.*')
            en
            let validremote = '\.\%(git\)\=\|\.\=/.*\|[[:alnum:]_-]\+\%(://.\{-\}\)\='
            if arg ==# '-'
                let remote = ''
                let rev = ''
                let result = fugitive#Result()
                if filereadable(get(result, 'file', ''))
                    let rev = s:fnameescape(result.file)
                el
                    return 'echoerr ' . string('fugitive: could not find prior :Git invocation')
                en
            elseif !exists('l:remote')
                let remote = matchstr(arg, '@\zs\%('.validremote.'\)$')
                let rev = substitute(arg, '@\%('.validremote.'\)$','','')
            el
                let rev = arg
            en
            if rev =~? '^\a\a\+:[\/][\/]' && rev !~? '^fugitive:'
                let rev = substitute(rev, '\\\@<![#!]\|\\\@<!%\ze\w', '\\&', 'g')
            elseif rev ==# ':'
                let rev = ''
            en
            let expanded = s:Expand(rev)
            if expanded =~? '^\a\a\+:[\/][\/]' && expanded !~? '^fugitive:'
                return s:BrowserOpen(s:Slash(expanded), a:mods, a:bang)
            en
            if !exists('l:result')
                let result = s:TempState(empty(expanded) ? bufnr('') : expanded)
            en
            if !empty(result) && filereadable(get(result, 'file', ''))
                for line in readfile(result.file, '', 4096)
                    let rev = s:fnameescape(matchstr(line, '\<https\=://[^[:space:]<>]*[^[:space:]<>.,;:"''!?]'))
                    if len(rev)
                        return s:BrowserOpen(rev, a:mods, a:bang)
                    en
                endfor
                return 'echoerr ' . string('fugitive: no URL found in output of :Git')
            en
            exe s:DirCheck(dir)
            if empty(expanded)
                let bufname = &buftype =~# '^\%(nofile\|terminal\)$' ? '' : s:BufName('%')
                let expanded = s:DirRev(bufname)[1]
                if empty(expanded)
                    let expanded = fugitive#Path(bufname, ':(top)', dir)
                en
                if a:count > 0 && bufname !=# bufname('')
                    let blame = s:BlameCommitFileLnum(getline(a:count))
                    if len(blame[0])
                        let expanded = blame[0]
                    en
                en
            en
            let refdir = fugitive#Find('.git/refs', dir)
            for subdir in ['tags/', 'heads/', 'remotes/']
                if expanded !~# '^[./]' && filereadable(refdir . '/' . subdir . expanded)
                    let expanded = '.git/refs/' . subdir . expanded
                en
            endfor
            let full = s:Generate(expanded, dir)
            let commit = ''
            if full =~? '^fugitive:'
                let [dir, commit, path] = s:DirCommitFile(full)
                if commit =~# '^:\=\d$'
                    let commit = ''
                en
                if commit =~ '..'
                    let type = s:TreeChomp(['cat-file','-t',commit.s:sub(path,'^/',':')], dir)
                    let branch = matchstr(expanded, '^[^:]*')
                elseif empty(path) || path ==# '/'
                    let type = 'tree'
                el
                    let type = 'blob'
                en
                let path = path[1:-1]
            elseif empty(s:Tree(dir))
                let path = '.git/' . full[strlen(dir)+1:-1]
                let type = ''
            el
                let path = fugitive#Path(full, '/')[1:-1]
                if path =~# '^\.git/'
                    let type = ''
                elseif isdirectory(full) || empty(path)
                    let type = 'tree'
                el
                    let type = 'blob'
                en
            en
            let config = fugitive#Config(dir)
            if type ==# 'tree' && !empty(path)
                let path = s:sub(path, '/\=$', '/')
            en
            let actual_dir = fugitive#Find('.git/', dir)
            if path =~# '^\.git/.*HEAD$' && filereadable(actual_dir . path[5:-1])
                let body = readfile(actual_dir . path[5:-1])[0]
                if body =~# '^\x\{40,\}$'
                    let commit = body
                    let type = 'commit'
                    let path = ''
                elseif body =~# '^ref: refs/'
                    let path = '.git/' . matchstr(body,'ref: \zs.*')
                en
            en

            let merge = ''
            if path =~# '^\.git/refs/remotes/.'
                if empty(remote)
                    let remote = matchstr(path, '^\.git/refs/remotes/\zs[^/]\+')
                    let branch = matchstr(path, '^\.git/refs/remotes/[^/]\+/\zs.\+')
                el
                    let merge = matchstr(path, '^\.git/refs/remotes/[^/]\+/\zs.\+')
                    let branch = merge
                    let path = '.git/refs/heads/'.merge
                en
            elseif path =~# '^\.git/refs/heads/.'
                let branch = path[16:-1]
            elseif !exists('branch')
                let branch = FugitiveHead(0, dir)
            en
            if !empty(branch)
                let r = FugitiveConfigGet('branch.'.branch.'.remote', config)
                let m = FugitiveConfigGet('branch.'.branch.'.merge', config)[11:-1]
                if r ==# '.' && !empty(m)
                    let r2 = FugitiveConfigGet('branch.'.m.'.remote', config)
                    if r2 !~# '^\.\=$'
                        let r = r2
                        let m = FugitiveConfigGet('branch.'.m.'.merge', config)[11:-1]
                    en
                en
                if empty(remote)
                    let remote = r
                en
                if r ==# '.' || r ==# remote
                    let remote_ref = 'refs/remotes/' . remote . '/' . branch
                    if FugitiveConfigGet('push.default', config) ==# 'upstream' ||
                                \ !filereadable(FugitiveFind('.git/' . remote_ref, dir)) && empty(s:ChompDefault('', ['rev-parse', '--verify', remote_ref, '--'], dir))
                        let merge = m
                        if path =~# '^\.git/refs/heads/.'
                            let path = '.git/refs/heads/'.merge
                        en
                    el
                        let merge = branch
                    en
                en
            en

            let line1 = a:count > 0 && type ==# 'blob' ? a:line1 : 0
            let line2 = a:count > 0 && type ==# 'blob' ? a:count : 0
            if empty(commit) && path !~# '^\.git/'
                if a:count < 0 && !empty(merge)
                    let commit = merge
                el
                    let commit = ''
                    if len(merge)
                        let owner = s:Owner(@%, dir)
                        let commit = s:ChompDefault('', ['merge-base', 'refs/remotes/' . remote . '/' . merge, empty(owner) ? '@' : owner, '--'], dir)
                        if line2 > 0 && empty(arg) && commit =~# '^\x\{40,\}$'
                            let blame_list = tempname()
                            call writefile([commit, ''], blame_list, 'b')
                            let blame_in = tempname()
                            silent exe 'noautocmd keepalt %write' blame_in
                            let [blame, exec_error] = s:LinesError(['-c', 'blame.coloring=none', 'blame', '--contents', blame_in, '-L', line1.','.line2, '-S', blame_list, '-s', '--show-number', './' . path], dir)
                            if !exec_error
                                let blame_regex = '^\^\x\+\s\+\zs\d\+\ze\s'
                                if get(blame, 0) =~# blame_regex && get(blame, -1) =~# blame_regex
                                    let line1 = +matchstr(blame[0], blame_regex)
                                    let line2 = +matchstr(blame[-1], blame_regex)
                                el
                                    throw "fugitive: can't browse to uncommitted change"
                                en
                            en
                        en
                    en
                en
                if empty(commit)
                    let commit = readfile(fugitive#Find('.git/HEAD', dir), '', 1)[0]
                en
                let i = 0
                while commit =~# '^ref: ' && i < 10
                    let ref_file = refdir[0 : -5] . commit[5:-1]
                    if getfsize(ref_file) > 0
                        let commit = readfile(ref_file, '', 1)[0]
                    el
                        let commit = fugitive#RevParse(commit[5:-1], dir)
                    en
                    let i -= 1
                endwhile
            en

            if empty(remote) || remote ==# '.'
                let remote = s:RemoteDefault(config)
            en
            if remote =~# ':'
                let remote_url = remote
            el
                let remote_url = fugitive#RemoteUrl(remote, config)
            en
            let raw = empty(remote_url) ? remote : remote_url
            let git_dir = s:GitDir(dir)

            let opts = {
                        \ 'git_dir': git_dir,
                        \ 'repo': {'git_dir': git_dir},
                        \ 'remote': raw,
                        \ 'remote_name': remote,
                        \ 'commit': commit,
                        \ 'path': path,
                        \ 'type': type,
                        \ 'line1': line1,
                        \ 'line2': line2}

            let url = ''
            for Handler in get(g:, 'fugitive_browse_handlers', [])
                let url = call(Handler, [copy(opts)])
                if !empty(url)
                    break
                en
            endfor

            if empty(url)
                throw "fugitive: no GBrowse handler installed for '".raw."'"
            en

            return s:BrowserOpen(url, a:mods, a:bang)
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
    endf

" Section: Go to file

    let s:ref_header = '\%(Merge\|Rebase\|Upstream\|Pull\|Push\)'

    nno  <SID>: :<C-U><C-R>=v:count ? v:count : ''<CR>
    fun! fugitive#MapCfile(...) abort
        exe 'cnoremap <buffer> <expr> <Plug><cfile>' (a:0 ? a:1 : 'fugitive#Cfile()')
        let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') . '|sil! exe "cunmap <buffer> <Plug><cfile>"'
        if !exists('g:fugitive_no_maps')
            call s:Map('n', 'gf',          '<SID>:find <Plug><cfile><CR>', '<silent><unique>', 1)
            call s:Map('n', '<C-W>f',     '<SID>:sfind <Plug><cfile><CR>', '<silent><unique>', 1)
            call s:Map('n', '<C-W><C-F>', '<SID>:sfind <Plug><cfile><CR>', '<silent><unique>', 1)
            call s:Map('n', '<C-W>gf',  '<SID>:tabfind <Plug><cfile><CR>', '<silent><unique>', 1)
            call s:Map('c', '<C-R><C-F>', '<Plug><cfile>', '<silent><unique>', 1)
        en
    endf

    fun! s:ContainingCommit() abort
        let commit = s:Owner(@%)
        return empty(commit) ? '@' : commit
    endf

    fun! s:SquashArgument(...) abort
        if &filetype == 'fugitive'
            let commit = matchstr(getline('.'), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\{4,\}\ze \|^' . s:ref_header . ': \zs\S\+')
        elseif has_key(s:temp_files, s:cpath(expand('%:p')))
            let commit = matchstr(getline('.'), '\S\@<!\x\{4,\}\>')
        el
            let commit = s:Owner(@%)
        en
        return len(commit) && a:0 ? printf(a:1, commit) : commit
    endf

    fun! s:RebaseArgument() abort
        return s:SquashArgument(' %s^')
    endf

    fun! s:NavigateUp(count) abort
        let rev = substitute(s:DirRev(@%)[1], '^$', ':', 'g')
        let c = a:count
        while c
            if rev =~# ':.*/.'
                let rev = matchstr(rev, '.*\ze/.\+', '')
            elseif rev =~# '.:.'
                let rev = matchstr(rev, '^.[^:]*:')
            elseif rev =~# '^:'
                let rev = '@^{}'
            elseif rev =~# ':$'
                let rev = rev[0:-2]
            el
                return rev.'~'.c
            en
            let c -= 1
        endwhile
        return rev
    endf

    fun! s:MapMotion(lhs, rhs) abort
        let maps = [
                    \ s:Map('n', a:lhs, ":<C-U>" . a:rhs . "<CR>", "<silent>"),
                    \ s:Map('o', a:lhs, ":<C-U>" . a:rhs . "<CR>", "<silent>"),
                    \ s:Map('x', a:lhs, ":<C-U>exe 'normal! gv'<Bar>" . a:rhs . "<CR>", "<silent>")]
        call filter(maps, '!empty(v:val)')
        return join(maps, '|')
    endf

    fun! fugitive#MapJumps(...) abort
        if !&modifiable
            if get(b:, 'fugitive_type', '') ==# 'blob'
                let blame_tail = '<C-R>=v:count ? " --reverse" : ""<CR><CR>'
                exe s:Map('n', '<2-LeftMouse>', ':<C-U>0,1Git ++curwin blame' . blame_tail, '<silent>')
                exe s:Map('n', '<CR>', ':<C-U>0,1Git ++curwin blame' . blame_tail, '<silent>')
                exe s:Map('n', 'o',    ':<C-U>0,1Git blame' . blame_tail, '<silent>')
                exe s:Map('n', 'p',    ':<C-U>0,1Git blame!' . blame_tail, '<silent>')
                if has('patch-7.4.1898')
                    exe s:Map('n', 'gO',   ':<C-U>vertical 0,1Git blame' . blame_tail, '<silent>')
                    exe s:Map('n', 'O',    ':<C-U>tab 0,1Git blame' . blame_tail, '<silent>')
                el
                    exe s:Map('n', 'gO',   ':<C-U>0,4Git blame' . blame_tail, '<silent>')
                    exe s:Map('n', 'O',    ':<C-U>0,5Git blame' . blame_tail, '<silent>')
                en

                call s:Map('n', 'D', ":echoerr 'fugitive: D has been removed in favor of dd'<CR>", '<silent><unique>')
                call s:Map('n', 'dd', ":<C-U>call fugitive#DiffClose()<Bar>Gdiffsplit!<CR>", '<silent>')
                call s:Map('n', 'dh', ":<C-U>call fugitive#DiffClose()<Bar>Ghdiffsplit!<CR>", '<silent>')
                call s:Map('n', 'ds', ":<C-U>call fugitive#DiffClose()<Bar>Ghdiffsplit!<CR>", '<silent>')
                call s:Map('n', 'dv', ":<C-U>call fugitive#DiffClose()<Bar>Gvdiffsplit!<CR>", '<silent>')
                call s:Map('n', 'd?', ":<C-U>help fugitive_d<CR>", '<silent>')

            el
                call s:Map('n', '<2-LeftMouse>', ':<C-U>exe <SID>GF("edit")<CR>', '<silent>')
                call s:Map('n', '<CR>', ':<C-U>exe <SID>GF("edit")<CR>', '<silent>')
                call s:Map('n', 'o',    ':<C-U>exe <SID>GF("split")<CR>', '<silent>')
                call s:Map('n', 'gO',   ':<C-U>exe <SID>GF("vsplit")<CR>', '<silent>')
                call s:Map('n', 'O',    ':<C-U>exe <SID>GF("tabedit")<CR>', '<silent>')
                call s:Map('n', 'p',    ':<C-U>exe <SID>GF("pedit")<CR>', '<silent>')

                if !exists('g:fugitive_no_maps')
                    call s:Map('n', '<C-P>', ':exe <SID>PreviousItem(v:count1)<Bar>echohl WarningMsg<Bar>echo "CTRL-P is deprecated in favor of ("<Bar>echohl NONE<CR>', '<unique>')
                    call s:Map('n', '<C-N>', ':exe <SID>NextItem(v:count1)<Bar>echohl WarningMsg<Bar>echo "CTRL-N is deprecated in favor of )"<Bar>echohl NONE<CR>', '<unique>')
                en
                call s:MapMotion('(', 'exe <SID>PreviousItem(v:count1)')
                call s:MapMotion(')', 'exe <SID>NextItem(v:count1)')
                call s:MapMotion('K', 'exe <SID>PreviousHunk(v:count1)')
                call s:MapMotion('J', 'exe <SID>NextHunk(v:count1)')
                call s:MapMotion('[c', 'exe <SID>PreviousHunk(v:count1)')
                call s:MapMotion(']c', 'exe <SID>NextHunk(v:count1)')
                call s:MapMotion('[/', 'exe <SID>PreviousFile(v:count1)')
                call s:MapMotion(']/', 'exe <SID>NextFile(v:count1)')
                call s:MapMotion('[m', 'exe <SID>PreviousFile(v:count1)')
                call s:MapMotion(']m', 'exe <SID>NextFile(v:count1)')
                call s:MapMotion('[[', 'exe <SID>PreviousSection(v:count1)')
                call s:MapMotion(']]', 'exe <SID>NextSection(v:count1)')
                call s:MapMotion('[]', 'exe <SID>PreviousSectionEnd(v:count1)')
                call s:MapMotion('][', 'exe <SID>NextSectionEnd(v:count1)')
                call s:Map('nxo', '*', '<SID>PatchSearchExpr(0)', '<expr>')
                call s:Map('nxo', '#', '<SID>PatchSearchExpr(1)', '<expr>')
            en
            call s:Map('n', 'S',    ':<C-U>echoerr "Use gO"<CR>', '<silent><unique>')
            call s:Map('n', 'dq', ":<C-U>call fugitive#DiffClose()<CR>", '<silent>')
            call s:Map('n', '-', ":<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>NavigateUp(v:count1))<Bar> if getline(1) =~# '^tree \x\{40,\}$' && empty(getline(2))<Bar>call search('^'.escape(expand('#:t'),'.*[]~\').'/\=$','wc')<Bar>endif<CR>", '<silent>')
            call s:Map('n', 'P',     ":<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit().'^'.v:count1.<SID>Relative(':'))<CR>", '<silent>')
            call s:Map('n', '~',     ":<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit().'~'.v:count1.<SID>Relative(':'))<CR>", '<silent>')
            call s:Map('n', 'C',     ":<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>", '<silent>')
            call s:Map('n', 'cp',    ":<C-U>echoerr 'Use gC'<CR>", '<silent><unique>')
            call s:Map('n', 'gC',    ":<C-U>exe 'Gpedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>", '<silent>')
            call s:Map('n', 'gc',    ":<C-U>exe 'Gpedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>", '<silent>')
            call s:Map('n', 'gi',    ":<C-U>exe 'Gsplit' (v:count ? '.gitignore' : '.git/info/exclude')<CR>", '<silent>')
            call s:Map('x', 'gi',    ":<C-U>exe 'Gsplit' (v:count ? '.gitignore' : '.git/info/exclude')<CR>", '<silent>')

            call s:Map('n', 'c<Space>', ':Git commit<Space>')
            call s:Map('n', 'c<CR>', ':Git commit<CR>')
            call s:Map('n', 'cv<Space>', ':tab Git commit -v<Space>')
            call s:Map('n', 'cv<CR>', ':tab Git commit -v<CR>')
            call s:Map('n', 'ca', ':<C-U>Git commit --amend<CR>', '<silent>')
            call s:Map('n', 'cc', ':<C-U>Git commit<CR>', '<silent>')
            call s:Map('n', 'ce', ':<C-U>Git commit --amend --no-edit<CR>', '<silent>')
            call s:Map('n', 'cw', ':<C-U>Git commit --amend --only<CR>', '<silent>')
            call s:Map('n', 'cva', ':<C-U>tab Git commit -v --amend<CR>', '<silent>')
            call s:Map('n', 'cvc', ':<C-U>tab Git commit -v<CR>', '<silent>')
            call s:Map('n', 'cRa', ':<C-U>Git commit --reset-author --amend<CR>', '<silent>')
            call s:Map('n', 'cRe', ':<C-U>Git commit --reset-author --amend --no-edit<CR>', '<silent>')
            call s:Map('n', 'cRw', ':<C-U>Git commit --reset-author --amend --only<CR>', '<silent>')
            call s:Map('n', 'cf', ':<C-U>Git commit --fixup=<C-R>=<SID>SquashArgument()<CR>')
            call s:Map('n', 'cF', ':<C-U><Bar>Git -c sequence.editor=true rebase --interactive --autosquash<C-R>=<SID>RebaseArgument()<CR><Home>Git commit --fixup=<C-R>=<SID>SquashArgument()<CR>')
            call s:Map('n', 'cs', ':<C-U>Git commit --no-edit --squash=<C-R>=<SID>SquashArgument()<CR>')
            call s:Map('n', 'cS', ':<C-U><Bar>Git -c sequence.editor=true rebase --interactive --autosquash<C-R>=<SID>RebaseArgument()<CR><Home>Git commit --no-edit --squash=<C-R>=<SID>SquashArgument()<CR>')
            call s:Map('n', 'cA', ':<C-U>Git commit --edit --squash=<C-R>=<SID>SquashArgument()<CR>')
            call s:Map('n', 'c?', ':<C-U>help fugitive_c<CR>', '<silent>')

            call s:Map('n', 'cr<Space>', ':Git revert<Space>')
            call s:Map('n', 'cr<CR>', ':Git revert<CR>')
            call s:Map('n', 'crc', ':<C-U>Git revert <C-R>=<SID>SquashArgument()<CR><CR>', '<silent>')
            call s:Map('n', 'crn', ':<C-U>Git revert --no-commit <C-R>=<SID>SquashArgument()<CR><CR>', '<silent>')
            call s:Map('n', 'cr?', ':<C-U>help fugitive_cr<CR>', '<silent>')

            call s:Map('n', 'cm<Space>', ':Git merge<Space>')
            call s:Map('n', 'cm<CR>', ':Git merge<CR>')
            call s:Map('n', 'cmt', ':Git mergetool')
            call s:Map('n', 'cm?', ':<C-U>help fugitive_cm<CR>', '<silent>')

            call s:Map('n', 'cz<Space>', ':Git stash<Space>')
            call s:Map('n', 'cz<CR>', ':Git stash<CR>')
            call s:Map('n', 'cza', ':<C-U>Git stash apply --quiet --index stash@{<C-R>=v:count<CR>}<CR>')
            call s:Map('n', 'czA', ':<C-U>Git stash apply --quiet stash@{<C-R>=v:count<CR>}<CR>')
            call s:Map('n', 'czp', ':<C-U>Git stash pop --quiet --index stash@{<C-R>=v:count<CR>}<CR>')
            call s:Map('n', 'czP', ':<C-U>Git stash pop --quiet stash@{<C-R>=v:count<CR>}<CR>')
            call s:Map('n', 'czs', ':<C-U>Git stash push --staged<CR>')
            call s:Map('n', 'czv', ':<C-U>exe "Gedit" fugitive#RevParse("stash@{" . v:count . "}")<CR>', '<silent>')
            call s:Map('n', 'czw', ':<C-U>Git stash push --keep-index<C-R>=v:count > 1 ? " --all" : v:count ? " --include-untracked" : ""<CR><CR>')
            call s:Map('n', 'czz', ':<C-U>Git stash push <C-R>=v:count > 1 ? " --all" : v:count ? " --include-untracked" : ""<CR><CR>')
            call s:Map('n', 'cz?', ':<C-U>help fugitive_cz<CR>', '<silent>')

            call s:Map('n', 'co<Space>', ':Git checkout<Space>')
            call s:Map('n', 'co<CR>', ':Git checkout<CR>')
            call s:Map('n', 'coo', ':<C-U>Git checkout <C-R>=substitute(<SID>SquashArgument(),"^$",get(<SID>TempState(),"filetype","") ==# "git" ? expand("<cfile>") : "","")<CR> --<CR>')
            call s:Map('n', 'co?', ':<C-U>help fugitive_co<CR>', '<silent>')

            call s:Map('n', 'cb<Space>', ':Git branch<Space>')
            call s:Map('n', 'cb<CR>', ':Git branch<CR>')
            call s:Map('n', 'cb?', ':<C-U>help fugitive_cb<CR>', '<silent>')

            call s:Map('n', 'r<Space>', ':Git rebase<Space>')
            call s:Map('n', 'r<CR>', ':Git rebase<CR>')
            call s:Map('n', 'ri', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><CR>', '<silent>')
            call s:Map('n', 'rf', ':<C-U>Git -c sequence.editor=true rebase --interactive --autosquash<C-R>=<SID>RebaseArgument()<CR><CR>', '<silent>')
            call s:Map('n', 'ru', ':<C-U>Git rebase --interactive @{upstream}<CR>', '<silent>')
            call s:Map('n', 'rp', ':<C-U>Git rebase --interactive @{push}<CR>', '<silent>')
            call s:Map('n', 'rw', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/reword/e<CR>', '<silent>')
            call s:Map('n', 'rm', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/edit/e<CR>', '<silent>')
            call s:Map('n', 'rd', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>', '<silent>')
            call s:Map('n', 'rk', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>', '<silent>')
            call s:Map('n', 'rx', ':<C-U>Git rebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>', '<silent>')
            call s:Map('n', 'rr', ':<C-U>Git rebase --continue<CR>', '<silent>')
            call s:Map('n', 'rs', ':<C-U>Git rebase --skip<CR>', '<silent>')
            call s:Map('n', 're', ':<C-U>Git rebase --edit-todo<CR>', '<silent>')
            call s:Map('n', 'ra', ':<C-U>Git rebase --abort<CR>', '<silent>')
            call s:Map('n', 'r?', ':<C-U>help fugitive_r<CR>', '<silent>')

            call s:Map('n', '.',     ":<C-U> <C-R>=<SID>fnameescape(fugitive#Real(@%))<CR><Home>")
            call s:Map('x', '.',     ":<C-U> <C-R>=<SID>fnameescape(fugitive#Real(@%))<CR><Home>")
            call s:Map('n', 'g?',    ":<C-U>help fugitive-map<CR>", '<silent>')
            call s:Map('n', '<F1>',  ":<C-U>help fugitive-map<CR>", '<silent>')
        en

        let old_browsex = maparg('<Plug>NetrwBrowseX', 'n')
        let new_browsex = substitute(old_browsex, '\Cnetrw#CheckIfRemote(\%(netrw#GX()\)\=)', '0', 'g')
        let new_browsex = substitute(new_browsex, 'netrw#GX()\|expand((exists("g:netrw_gx")? g:netrw_gx : ''<cfile>''))', 'fugitive#GX()', 'g')
        if new_browsex !=# old_browsex
            exe 'nnoremap <silent> <buffer> <Plug>NetrwBrowseX' new_browsex
        en
    endf

    fun! fugitive#GX() abort
        try
            let results = &filetype ==# 'fugitive' ? s:CfilePorcelain() : &filetype ==# 'git' ? s:cfile() : []
            if len(results) && len(results[0])
                return FugitiveReal(s:Generate(results[0]))
            en
        catch /^fugitive:/
        endtry
        return expand(get(g:, 'netrw_gx', expand('<cfile>')))
    endf

    fun! s:CfilePorcelain(...) abort
        let tree = s:Tree()
        if empty(tree)
            return ['']
        en
        let lead = s:cpath(tree, getcwd()) ? './' : tree . '/'
        let info = s:StageInfo()
        let line = getline('.')
        if len(info.sigil) && len(info.section) && len(info.paths)
            if info.section ==# 'Unstaged' && info.sigil !=# '-'
                return [lead . info.relative[0], info.offset, 'normal!zv']
            elseif info.section ==# 'Staged' && info.sigil ==# '-'
                return ['@:' . info.relative[0], info.offset, 'normal!zv']
            el
                return [':0:' . info.relative[0], info.offset, 'normal!zv']
            en
        elseif len(info.paths)
            return [lead . info.relative[0]]
        elseif len(info.commit)
            return [info.commit]
        elseif line =~# '^' . s:ref_header . ': \|^Head: '
            return [matchstr(line, ' \zs.*')]
        el
            return ['']
        en
    endf

    fun! fugitive#PorcelainCfile() abort
        let file = fugitive#Find(s:CfilePorcelain()[0])
        return empty(file) ? fugitive#Cfile() : s:fnameescape(file)
    endf

    fun! s:StatusCfile(...) abort
        let tree = s:Tree()
        if empty(tree)
            return []
        en
        let lead = s:cpath(tree, getcwd()) ? './' : tree . '/'
        if getline('.') =~# '^.\=\trenamed:.* -> '
            return [lead . matchstr(getline('.'),' -> \zs.*')]
        elseif getline('.') =~# '^.\=\t\(\k\| \)\+\p\?: *.'
            return [lead . matchstr(getline('.'),': *\zs.\{-\}\ze\%( ([^()[:digit:]]\+)\)\=$')]
        elseif getline('.') =~# '^.\=\t.'
            return [lead . matchstr(getline('.'),'\t\zs.*')]
        elseif getline('.') =~# ': needs merge$'
            return [lead . matchstr(getline('.'),'.*\ze: needs merge$')]
        elseif getline('.') =~# '^\%(. \)\=Not currently on any branch.$'
            return ['HEAD']
        elseif getline('.') =~# '^\%(. \)\=On branch '
            return ['refs/heads/'.getline('.')[12:]]
        elseif getline('.') =~# "^\\%(. \\)\=Your branch .*'"
            return [matchstr(getline('.'),"'\\zs\\S\\+\\ze'")]
        el
            return []
        en
    endf

    fun! fugitive#MessageCfile() abort
        let file = fugitive#Find(get(s:StatusCfile(), 0, ''))
        return empty(file) ? fugitive#Cfile() : s:fnameescape(file)
    endf

    fun! s:BranchCfile(result) abort
        return matchstr(getline('.'), '^. \zs\S\+')
    endf

    fun! s:cfile() abort
        let temp_state = s:TempState()
        let name = substitute(get(get(temp_state, 'args', []), 0, ''), '\%(^\|-\)\(\l\)', '\u\1', 'g')
        if exists('*s:' . name . 'Cfile')
            let cfile = s:{name}Cfile(temp_state)
            if !empty(cfile)
                return type(cfile) == type('') ? [cfile] : cfile
            en
        en
        if empty(FugitiveGitDir())
            return []
        en
        try
            let myhash = s:DirRev(@%)[1]
            if len(myhash)
                try
                    let myhash = fugitive#RevParse(myhash)
                catch /^fugitive:/
                    let myhash = ''
                endtry
            en
            if empty(myhash) && get(temp_state, 'filetype', '') ==# 'git'
                let lnum = line('.')
                while lnum > 0
                    if getline(lnum) =~# '^\%(commit\|tag\) \w'
                        let myhash = matchstr(getline(lnum),'^\w\+ \zs\S\+')
                        break
                    en
                    let lnum -= 1
                endwhile
            en

            let showtree = (getline(1) =~# '^tree ' && getline(2) == "")

            let treebase = substitute(s:DirCommitFile(@%)[1], '^\d$', ':&', '') . ':' .
                        \ s:Relative('') . (s:Relative('') =~# '^$\|/$' ? '' : '/')

            if getline('.') =~# '^\d\{6\} \l\{3,8\} \x\{40,\}\t'
                return [treebase . s:sub(matchstr(getline('.'),'\t\zs.*'),'/$','')]
            elseif showtree
                return [treebase . s:sub(getline('.'),'/$','')]

            el

                let dcmds = []

                " Index
                if getline('.') =~# '^\d\{6\} \x\{40,\} \d\t'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    let file = ':'.s:sub(matchstr(getline('.'),'\d\t.*'),'\t',':')
                    return [file]
                en

                if getline('.') =~# '^ref: '
                    let ref = strpart(getline('.'),5)

                elseif getline('.') =~# '^\%([|/\\_ ]*\*[|/\\_ ]*\)\=commit \x\{40,\}\>'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    return [ref]

                elseif getline('.') =~# '^parent \x\{40,\}\>'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    let line = line('.')
                    let parent = 0
                    while getline(line) =~# '^parent '
                        let parent += 1
                        let line -= 1
                    endwhile
                    return [ref]

                elseif getline('.') =~# '^tree \x\{40,\}$'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    if len(myhash) && fugitive#RevParse(myhash.':') ==# ref
                        let ref = myhash.':'
                    en
                    return [ref]

                elseif getline('.') =~# '^object \x\{40,\}$' && getline(line('.')+1) =~ '^type \%(commit\|tree\|blob\)$'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    let type = matchstr(getline(line('.')+1),'type \zs.*')

                elseif getline('.') =~# '^\l\{3,8\} '.myhash.'$'
                    let ref = s:DirRev(@%)[1]

                elseif getline('.') =~# '^\l\{3,8\} \x\{40,\}\>'
                    let ref = matchstr(getline('.'),'\x\{40,\}')
                    echoerr "warning: unknown context ".matchstr(getline('.'),'^\l*')

                elseif getline('.') =~# '^[A-Z]\d*\t\S' && len(myhash)
                    let files = split(getline('.'), "\t")[1:-1]
                    let ref = 'b/' . files[-1]
                    if getline('.') =~# '^D'
                        let ref = 'a/' . files[0]
                    elseif getline('.') !~# '^A'
                        let dcmds = ['', 'Gdiffsplit! >' . myhash . '^:' . fnameescape(files[0])]
                    en

                elseif getline('.') =~# '^[+-]\{3\} [abciow12]\=/'
                    let ref = getline('.')[4:]

                elseif getline('.') =~# '^[+-]' && search('^@@ -\d\+\%(,\d\+\)\= +\d\+','bnW')
                    let type = getline('.')[0]
                    let lnum = line('.') - 1
                    let offset = 0
                    while getline(lnum) !~# '^@@ -\d\+\%(,\d\+\)\= +\d\+'
                        if getline(lnum) =~# '^[ '.type.']'
                            let offset += 1
                        en
                        let lnum -= 1
                    endwhile
                    let offset += matchstr(getline(lnum), type.'\zs\d\+')
                    let ref = getline(search('^'.type.'\{3\} [abciow12]/','bnW'))[4:-1]
                    let dcmds = [offset, 'normal!zv']

                elseif getline('.') =~# '^rename from '
                    let ref = 'a/'.getline('.')[12:]
                elseif getline('.') =~# '^rename to '
                    let ref = 'b/'.getline('.')[10:]

                elseif getline('.') =~# '^@@ -\d\+\%(,\d\+\)\= +\d\+'
                    let diff = getline(search('^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)', 'bcnW'))
                    let offset = matchstr(getline('.'), '+\zs\d\+')

                    let dref = matchstr(diff, '\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
                    let ref = matchstr(diff, '\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
                    let dcmd = 'Gdiffsplit! +'.offset

                elseif getline('.') =~# '^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)'
                    let dref = matchstr(getline('.'),'\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
                    let ref = matchstr(getline('.'),'\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
                    let dcmd = 'Gdiffsplit!'

                elseif getline('.') =~# '^index ' && getline(line('.')-1) =~# '^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)'
                    let line = getline(line('.')-1)
                    let dref = matchstr(line,'\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
                    let ref = matchstr(line,'\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
                    let dcmd = 'Gdiffsplit!'

                elseif line('$') == 1 && getline('.') =~ '^\x\{40,\}$'
                    let ref = getline('.')

                elseif expand('<cword>') =~# '^\x\{7,\}\>'
                    return [expand('<cword>')]

                el
                    let ref = ''
                en

                let prefixes = {
                            \ '1': '',
                            \ '2': '',
                            \ 'b': ':0:',
                            \ 'i': ':0:',
                            \ 'o': '',
                            \ 'w': ''}

                if len(myhash)
                    let prefixes.a = myhash.'^:'
                    let prefixes.b = myhash.':'
                en
                let ref = substitute(ref, '^\(\w\)/', '\=get(prefixes, submatch(1), "@:")', '')
                if exists('dref')
                    let dref = substitute(dref, '^\(\w\)/', '\=get(prefixes, submatch(1), "@:")', '')
                en

                if ref ==# '/dev/null'
                    " Empty blob
                    let ref = 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391'
                en

                if exists('dref')
                    return [ref, dcmd . ' >' . s:fnameescape(dref)] + dcmds
                elseif ref != ""
                    return [ref] + dcmds
                en

            en
            return []
        endtry
    endf

    fun! s:GF(mode) abort
        try
            let results = &filetype ==# 'fugitive' ? s:CfilePorcelain() : &filetype ==# 'gitcommit' ? s:StatusCfile() : s:cfile()
        catch /^fugitive:/
            return 'echoerr ' . string(v:exception)
        endtry
        if len(results) > 1
            let cmd = 'G' . a:mode .
                        \ (empty(results[1]) ? '' : ' +' . s:PlusEscape(results[1])) . ' ' .
                        \ fnameescape(results[0])
            let tail = join(map(results[2:-1], '"|" . v:val'), '')
            if a:mode ==# 'pedit' && len(tail)
                return cmd . '|wincmd P|exe ' . string(tail[1:-1]) . '|wincmd p'
            el
                return cmd . tail
            en
        elseif len(results) && len(results[0])
            return 'G' . a:mode . ' ' . s:fnameescape(results[0])
        el
            return ''
        en
    endf

    fun! fugitive#Cfile() abort
        let pre = ''
        let results = s:cfile()
        if empty(results)
            if !empty(s:TempState())
                let cfile = s:TempDotMap()
                if !empty(cfile)
                    return fnameescape(s:Generate(cfile))
                en
            en
            let cfile = expand('<cfile>')
            if &includeexpr =~# '\<v:fname\>'
                sandbox let cfile = eval(substitute(&includeexpr, '\C\<v:fname\>', '\=string(cfile)', 'g'))
            en
            return cfile
        elseif len(results) > 1
            let pre = '+' . join(map(results[1:-1], 'escape(v:val, " ")'), '\|') . ' '
        en
        return pre . fnameescape(s:Generate(results[0]))
    endf

" Section: Statusline

    fun! fugitive#Statusline(...) abort
        let dir = s:Dir(bufnr(''))
        if empty(dir)
            return ''
        en
        let status = ''
        let commit = s:DirCommitFile(@%)[1]
        if len(commit)
            let status .= ':' . commit[0:6]
        en
        let status .= '('.FugitiveHead(7, dir).')'
        return '[Git'.status.']'
    endf

    fun! fugitive#statusline(...) abort
        return fugitive#Statusline()
    endf

    fun! fugitive#head(...) abort
        if empty(s:Dir())
            return ''
        en

        return fugitive#Head(a:0 ? a:1 : 0)
    endf

" Section: Folding

    fun! fugitive#Foldtext() abort
        if &foldmethod !=# 'syntax'
            return foldtext()
        en

        let line_foldstart = getline(v:foldstart)
        if line_foldstart =~# '^diff '
            let [add, remove] = [-1, -1]
            let filename = ''
            for lnum in range(v:foldstart, v:foldend)
                let line = getline(lnum)
                if filename ==# '' && line =~# '^[+-]\{3\} [abciow12]/'
                    let filename = line[6:-1]
                en
                if line =~# '^+'
                    let add += 1
                elseif line =~# '^-'
                    let remove += 1
                elseif line =~# '^Binary '
                    let binary = 1
                en
            endfor
            if filename ==# ''
                let filename = matchstr(line_foldstart, '^diff .\{-\} [abciow12]/\zs.*\ze [abciow12]/')
            en
            if filename ==# ''
                let filename = line_foldstart[5:-1]
            en
            if exists('binary')
                return 'Binary: '.filename
            el
                return '+-' . v:folddashes . ' ' . (add<10&&remove<100?' ':'') . add . '+ ' . (remove<10&&add<100?' ':'') . remove . '- ' . filename
            en
        elseif line_foldstart =~# '^@@\+ .* @@'
            return '+-' . v:folddashes . ' ' . line_foldstart
        elseif &filetype ==# 'gitcommit' && line_foldstart =~# '^# .*:$'
            let lines = getline(v:foldstart, v:foldend)
            call filter(lines, 'v:val =~# "^#\t"')
            cal map(lines, "s:sub(v:val, '^#\t%(modified: +|renamed: +)=', '')")
            cal map(lines, "s:sub(v:val, '^([[:alpha:] ]+): +(.*)', '\\2 (\\1)')")
            return line_foldstart.' '.join(lines, ', ')
        en
        return foldtext()
    endf

    fun! fugitive#foldtext() abort
        return fugitive#Foldtext()
    endf

" Section: Initialization
    fun! fugitive#Init() abort
        throw 'Third party code is using fugitive#Init() which has been removed. Contact the author if you have a reason to still use it'
    endf

    fun! fugitive#is_git_dir(path) abort
        throw 'Third party code is using fugitive#is_git_dir() which has been removed. Change it to FugitiveIsGitDir()'
    endf

    fun! fugitive#extract_git_dir(path) abort
        throw 'Third party code is using fugitive#extract_git_dir() which has been removed. Change it to FugitiveExtractGitDir()'
    endf

    fun! fugitive#detect(path) abort
        throw 'Third party code is using fugitive#detect() which has been removed. Contact the author if you have a reason to still use it'
    endf

