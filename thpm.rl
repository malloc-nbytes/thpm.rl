#!/usr/local/bin/earl

module ThPm

import "std/io.rl"; as io
import "std/system.rl"; as sys
import "std/parsers/toml.rl"; as toml
import "std/parsers/basic-lexer.rl"; as lexer
import "std/datatypes/char.rl";
import "std/colors.rl"; as colors
import "std/time.rl"; as time

set_flag("-S");

enum Flag_Type {
    None = 1 << 0,
    Yes = 1 << 1,
    Verbose = 1 << 2,
}

enum Config {
    Path = format(env("HOME"), "/.thpm"),
    Persist_Name = "__thpm__old_pkgs",
    Tmp_Pkg_Name = "__thpm_tmp_pkg",
}

let FLAGS = 0x00;

fn log(msg, c) {
    println(c, msg, colors::Te.Reset);
}

fn log2(msg, c) {
    println(c + colors::Te.Bold, f"*** {msg}", colors::Te.Reset);
}

fn get_install_paths(config): list {
    return parse_list_syntax(str(config["thpm_config"].unwrap()["install_paths"].unwrap()));
}

fn get_size_of_installed_pkg(config, name) {
    with paths = get_install_paths(config)
    in foreach path in paths {
        foreach f in sys::ls(path) {
            if str_match_ci([io::strip_path(f)], name) {
                $f"du -k {f} | cut -f1" |> let size;
                return some((size, f));
            }
        }
    }
    return none;
}

fn parse_list_syntax(line: str): list {
    let items = [];
    let lex = lexer::T(line);
    assert(lex.next().ty == lexer::TokenType.LSquareBracket);

    if lex.peek() && lex.peek().unwrap().ty == lexer::TokenType.RSquareBracket {
        return items;
    }

    while lex.peek() && lex.peek().unwrap().ty != lexer::EOF {
        let s = lex.next();
        assert(s.ty == lexer::TokenType.Strlit);
        items += [s.lx];
        if lex.peek() && lex.peek().unwrap().ty == lexer::TokenType.Comma {
            let _ = lex.next();
        } else {
            assert(lex.peek() && lex.peek().unwrap().ty == lexer::TokenType.RSquareBracket);
            break;
        }
    }

    return items;
}

fn name_exists_in_config(config, name) {
    foreach k, v in config {
        if k == "thpm_config" { continue; }
        if k == name { return true; }
    }
    return false;
}

fn create_empty_config(install_paths, package_paths) {
    let f = open(Config.Path, "w");
    f.write("[thpm_config]\n");
    f.write(format("install_paths = ", install_paths, "\n"));
    f.write(format("package_paths = ", package_paths, "\n"));
    f.close();
}

fn init() {
    let ip = REPL_input("Enter installation paths in list format i.e., [\"/usr/local/bin\", \"/my/other/path\"]: ");
    let pp = REPL_input("Enter package paths in list format i.e., [/usr/local/bin]: ");
    return (ip, pp);
}

fn search_package_paths(config: dictionary, name: str): option {
    let paths = parse_list_syntax(str(config["thpm_config"].unwrap()["package_paths"].unwrap()));
    let path_proper = none;

    foreach path in paths {
        let files = sys::ls(path);
        foreach f in files {
            if io::strip_path(f) == name {
                path_proper = some(f);
                break;
            }
        }
        if path_proper { break; }
    }

    return path_proper;
}

fn uninstall_package(@ref config: dictionary, name: str) {
    let path = search_package_paths(config, name);

    if !path {
        panic(f"could not find package: `{name}`");
    }

    let uninstall = (parse_list_syntax(str(config[name].unwrap()["uninstall"].unwrap())));

    $"pwd" |> let cwd;

    cd(path.unwrap());
    uninstall.foreach(|u| {
        with parts = u.split(" ").filter(!= "")
        in if parts[0] == "cd" {
            assert(len(parts) == 2);
            cd(parts[1]);
        } else {
            $u;
        }
    });
    cd(cwd);

    config[name].unwrap().insert("installed", "false");
}

fn clone_pkg(config, name) {
    $format(parse_list_syntax(str(config[name].unwrap()["clone"].unwrap()))[0], " ./", Config.Tmp_Pkg_Name);
    let install_path = parse_list_syntax(str(config["thpm_config"].unwrap()["package_paths"].unwrap()))[0];
    let name_actual = config[name].unwrap()["name"].unwrap();
    $format("mv ./", Config.Tmp_Pkg_Name, f" {install_path}/{name_actual}");
    return f"{install_path}/{name_actual}";
}

fn execute_package(@ref config: dictionary, names: list) {
    let failed = [];
    with i = 0
    in foreach name in names {
        if !name_exists_in_config(config, name) {
            log(f"Package `{name}` does not exist", colors::Tfc.Red);
            failed += [name];
            continue;
        }

        with msg = case config[name].unwrap()["installed"].unwrap() == "true" of {
            true = "Reinstalling";
            _ = "Installing";
        }
        in log2(format(msg, ' ', names[i], " (", i+1, " of ", len(names), ")"), colors::Tfc.Green);
        sleep(time::ONE_SECOND);

        let path = search_package_paths(config, name);

        if !path {
            path = some(clone_pkg(config, name));
            println("PATH ::: ", path);
        }

        let build, install = (
            parse_list_syntax(str(config[name].unwrap()["build"].unwrap())),
            parse_list_syntax(str(config[name].unwrap()["install"].unwrap())),
        );

        $"pwd" |> let cwd;

        cd(path.unwrap());
        build.foreach(|b| {
                with parts = b.split(" ").filter(!= "")
                in if parts[0] == "cd" {
                    assert(len(parts) == 2);
                    cd(parts[1]);
                } else { $b; }
            });
        cd(path.unwrap());
        install.foreach(|i| {
                with parts = i.split(" ").filter(!= "")
                in if parts[0] == "cd" {
                    assert(len(parts) == 2);
                    cd(parts[1]);
                } else { $i; }
            });
        cd(cwd);

        config[name].unwrap().insert("installed", "true");

        i += 1;

        with sz = get_size_of_installed_pkg(config, name)
        in if sz {
            with s = sz.unwrap()[0],
                 p = sz.unwrap()[1]
            in log2(format("Total size of build: (", s, "KB) [", p,"]"), colors::Tfc.Green);
        } else {
            log2(format("Total size of build: (none)"), colors::Tfc.Green);
        }
        sleep(time::ONE_SECOND);
    }

    foreach fail in failed {
        log(f"Failed to install package `{fail}`", colors::Tfc.Red);
    }
}

fn new(@ref config: dictionary) {
    let clone, name, build, install, uninstall = (
        REPL_input("Enter the clone command i.e., [\"git clone https://www.github.com/user/repo.git\"]: "),
        REPL_input("Enter package name (must match the directory name): "),
        REPL_input("Enter build commands in a list syntax i.e., [\"cd build\", \"make -j12\"]: "),
        REPL_input("Enter install commands in a list syntax i.e., [\"cd build\", \"sudo make install\"]: "),
        REPL_input("Enter uninstall commands in a list syntax i.e., [\"cd build\", \"sudo make uninstall\"]: "),
    );

    config.insert(name, {
        "clone": clone,
        "name": name,
        "install": install,
        "build": build,
        "uninstall": uninstall,
        "installed": "false"
    });

    log(f"Added package {name}", colors::Tfc.Green);
}

fn usage() {
    println("Usage: thpm -- <option>");
    println("Options:");
    println("  h, help                - show this message");
    println("  n, new                 - create a new package entry");
    println("  l, ls                  - see installed packages");
    println("  i, install <name...>   - install a package");
    println("  u, update [name...]    - update package(s) or leave blank for all");
    println("  c, cmd <name...>       - view commands for package(s)");
    println("     uninstall <name...> - uninstall package(s)");
    println("     edit-installs       - manually edit the `installed` flag for packages");
    exit(0);
}

fn write_config(config: dictionary) {
    let f = open(Config.Path, "w");

    f.write("[thpm_config]\n");
    f.write(format("install_paths = ", config["thpm_config"].unwrap()["install_paths"].unwrap(), "\n"));
    f.write(format("package_paths = ", config["thpm_config"].unwrap()["package_paths"].unwrap(), "\n"));

    foreach k, v in config {
        if k == "thpm_config" { continue; }
        f.write(f"[{k}]\n");
        foreach i, j in v {
            f.write(f"{i} = {j}\n");
        }
    }

    f.close();
}

fn get_configured_packages(config: dictionary): list {
    let names = [];
    foreach k, v in config {
        if k == "thpm_config" { continue; }
        names += [v["name"].unwrap()];
    }
    return names;
}

fn str_match_ci(names, name) {
    if names.contains(name) { return true; }
    names = names.map(|s| {
        let buf = "";
        foreach c in s { buf += Char::tolower(c); }
        return buf;
    });
    return names.contains(name);
}

fn show_installed_packages(config: dictionary, silent: bool): int {
    let names = get_configured_packages(config);
    let installed = [];
    foreach k, v in config {
        if k == "thpm_config" { continue; }
        if v["installed"].unwrap() == "true" {
            installed += [k];
            if !silent { log(f"<*> {k}", colors::Tfc.Green); }
        } else {
            if !silent { log(f"< > {k}", colors::Tfc.Yellow); }
        }
    }
    return len(installed);
}

@world fn update(@ref config: dictionary, forced_names: list) {
    let paths = parse_list_syntax(str(config["thpm_config"].unwrap()["package_paths"].unwrap()));
    let names = get_configured_packages(config);
    let needs_reinstall = [];

    foreach path in paths {
        foreach f in sys::ls(path) {
            let strip = io::strip_path(f);
            let match1 = str_match_ci(names, strip);
            let match2 = match1 && len(forced_names) > 0 && str_match_ci(forced_names, strip);
            if (match1 && len(forced_names) == 0) || (len(forced_names) > 0 && match2) {
                cd(f);
                println(f"| Checking: {strip}");
                $"git rev-parse --abbrev-ref HEAD"                          |> let current_branch;
                $"git fetch origin"                                         |> let _;
                $f"git rev-parse {current_branch}"                          |> let local_commit;
                $f"git rev-parse origin/{current_branch}"                   |> let remote_commit;
                $f"git merge-base {current_branch} origin/{current_branch}" |> let base_commit;

                let show_hash = |_| {
                    log(f"| local hash: {local_commit}", colors::Tfc.Yellow);
                    log(f"| remote hash: {remote_commit}", colors::Tfc.Yellow);
                    log(f"| base hash: {base_commit}", colors::Tfc.Yellow);
                };

                if local_commit == remote_commit {
                    log(f"|-- Up to date.", colors::Tfc.Green + colors::Te.Bold);
                    print(colors::Te.Reset);
                } else if local_commit == base_commit {
                    show_hash();
                    $f"git diff {local_commit} {remote_commit}" |> let diff_output;
                    log(f"============= Diff =============", colors::Tfc.Yellow);
                    println(diff_output);
                    log(f"=========== End Diff ===========", colors::Tfc.Yellow);
                    let skip = false;
                    while true {
                        if (FLAGS `& Flag_Type.Yes) != 0 { break; }
                        let inp = REPL_input("Pull changes? [Y/n]: ");
                        if len(inp) == 0 || inp == "yes" || inp == "Yes" || inp == "y" || inp == "Y" {
                            break;
                        } else if inp == "no" || inp == "No" || inp == "n" || inp == "N" {
                            skip = true;
                            break;
                        } else {
                            println(f"Unknown input: `{inp}`");
                        }
                    }
                    if !skip {
                        log(f"|<- Behind, pulling changes...", colors::Tfc.Yellow);
                        $f"git pull";
                        log("Done", colors::Tfc.Green);
                        needs_reinstall += [strip];
                    }
                } else if remote_commit == base_commit {
                    show_hash();
                    log(f"|-> Ahead of remote, either restore changes or push.", colors::Tfc.Yellow);
                    println(f"    {f}");
                } else {
                    show_hash();
                    log(f"|-x Diverged from the remote. Manual intervention needed...", colors::Tfc.Red);
                    println(f"    {f}");
                }
            }
        }
    }

    execute_package(config, needs_reinstall);
}

fn show_cmds(config: dictionary, name: str) {
    if !config.has_key(name) { panic(f"{name} has no rules"); }
    log(f"Rules for {name}", colors::Tfc.Green);
    foreach k, v in config[name].unwrap() {
        println(f"{k} = {v}");
    }
}

fn str_is_num(s) {
    foreach c in s {
        if !Char::isnum(c) { return false; }
    }
    return true;
}

fn edit_installs(@ref config) {
    log("You can manually edit the `installed` flag for", colors::Tfc.Green);
    log("each package. This step is usefull for if you import", colors::Tfc.Green);
    log("your .thpm file from another machine where the `installed`", colors::Tfc.Green);
    log("flag may not be the same as this machine.", colors::Tfc.Green);
    log("Fields with `*` are marked as installed, and those that", colors::Tfc.Green);
    log("do not have it are marked as uninstalled.", colors::Tfc.Green);

    while true {
        let names = [];
        with idx = 0
        in foreach k, v in config {
            if k == "thpm_config" { continue; }
            print("[ ", len(names), " ] ");
            if v["installed"].unwrap() == "true" { print("<*>"); }
            else { print("< >"); }
            println(' ', v["name"].unwrap());
            idx += 1;
            names += [v["name"].unwrap()];
        }

        log("1.) Enter an index to flip the `installed` flag", colors::Tfc.Yellow);
        log("2.) Enter `*` to flip all of them", colors::Tfc.Yellow);
        log("3.) Leave blank to continue", colors::Tfc.Yellow);
        let inp = REPL_input("edit: ");
        if inp == ""             { break; }
        if inp == "*" {
            foreach @ref k, v in config {
                if k == "thpm_config" { continue; }
                v.insert("installed", str(!bool(v["installed"].unwrap())));
            }
        } else {
            if !str_is_num(inp) {
                log(f"Input: {inp} is not a number", colors::Tfc.Red);
            }
            else if int(inp) > len(names) {
                log(f"Input: {inp} not a valid index", colors::Tfc.Red);
            } else {
                let idx = int(inp);
                config[names[idx]].unwrap().insert("installed", str(!bool(config[names[idx]].unwrap()["installed"].unwrap())));
                log(format("Updated ", config[names[idx]].unwrap()["name"].unwrap()), colors::Tfc.Yellow);
            }
        }
    }
}

@pub @world fn thpm_main() {
    $format("touch ", Config.Path);
    let config = toml::parse(Config.Path);

    if config.empty() {
        let install_path, package_paths = init();
        create_empty_config(install_path, package_paths);
        exit(0);
    }

    if len(argv()) < 2 { usage(); }

    let args = argv()[1:];
    with i = 0
    in while i < len(args) {
        if args[i] == "-y" {
            FLAGS `|= Flag_Type.Yes;
            args.pop(i);
        } else if args[i] == "-v" {
            FLAGS `|= Flag_Type.Verbose;
            args.pop(i);
            set_flag("-x");
        } else {
            i += 1;
        }
    }

    with A = args
    in if A[0] == "h" || A[0] == "help" {
        usage();
    } else if A[0] == "n" || A[0] == "new" {
        new(config);
    } else if A[0] == "i" || A[0] == "install" {
        if len(A) < 2 { panic("install takes a name(s)"); }
        execute_package(config, A[1:]);
    } else if A[0] == "l" || A[0] == "ls" {
        let _ = show_installed_packages(config, false);
    } else if A[0] == "u" || A[0] == "update" {
        if len(A) > 1 { update(config, A[1:]); }
        else { update(config, []); }
    } else if A[0] == "uninstall" {
        if len(A) < 2 { panic("uninstall takes a name(s)"); }
        print(colors::Te.Bold + colors::Tfc.Red, "Uninstalling ", A[1:], " in: ");
        (1..=5).rev().foreach(|i| {
            print(i, ' ');
            flush();
            sleep(time::ONE_SECOND);
        });
        println(colors::Te.Reset);
        with parts = A[1:]
        in for i in 0 to len(parts) {
            log2(format("Uninstalling ", parts[i], " (", i+1, " of ", len(parts), ")"), colors::Tfc.Green);
            sleep(time::ONE_SECOND);
            uninstall_package(config, parts[i]);
        }
    } else if A[0] == "c" || A[0] == "cmd" {
        if len(A) < 2 { panic("cmd takes a name(s)"); }
        foreach name in A[1:] {
            show_cmds(config, name);
        }
    } else if A[0] == "edit-installs" {
        edit_installs(config);
    } else {
        usage();
    }

    write_config(config);
    let num_ipkgs, persist_ipkgs = (
        show_installed_packages(config, true),
        int(persist_lookup(Config.Persist_Name).unwrap()),
    );
    if num_ipkgs != persist_ipkgs {
        log(f"Installed number of packages update {persist_ipkgs} -> {num_ipkgs}", colors::Tfc.Yellow);
    }
    persist(Config.Persist_Name, num_ipkgs);
}

if !persist_lookup(Config.Persist_Name) {
    persist(Config.Persist_Name, 0);
}

thpm_main();
