#!/usr/local/bin/earl

module ThPm

import "std/io.rl"; as io
import "std/system.rl"; as sys
import "std/parsers/toml.rl"; as toml
import "std/parsers/basic-lexer.rl"; as lexer
import "std/datatypes/char.rl";
import "std/colors.rl"; as colors

enum Config {
    Path = format(env("HOME"), "/.thpm"),
    Persist_Name = "__thpm__old_pkgs",
}

fn log(msg, c) {
    println(c, msg, colors::Te.Reset);
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

fn create_empty_config(install_paths, package_paths) {
    print("opening: ", Config.Path);
    let f = open(Config.Path, "w");
    f.write("[thpm_config]\n");
    f.write(format("install_paths = ", install_paths, "\n"));
    f.write(format("package_paths = ", package_paths, "\n"));
    f.close();
}

fn init() {
    let ip = input("Enter installation paths in list format i.e., [\"/usr/local/bin\", \"/my/other/path\"]: ");
    let pp = input("Enter package paths in list format i.e., [/usr/local/bin]: ");
    let install_paths = parse_list_syntax(ip);
    let package_paths = parse_list_syntax(pp);
    return (install_paths, package_paths);
}

fn search_package_paths(config: dictionary, name: str): option {
    let paths = config["thpm_config"].unwrap()["package_paths"].unwrap();
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

fn uninstall_package(config: dictionary, name: str) {
    let path = search_package_paths(config, name);

    if !path {
        panic(f"could not find package: `{name}`");
    }

    log(f"Uninstalling {name}", colors::Tfc.Yellow);

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
}

fn execute_package(config: dictionary, name: str) {
    let path = search_package_paths(config, name);

    if !path {
        panic(f"could not find package: `{name}`");
    }

    log(f"Installing {name}", colors::Tfc.Green);

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
        } else {
            $b;
        }
    });
    cd(path.unwrap());
    install.foreach(|i| {
        with parts = i.split(" ").filter(!= "")
        in if parts[0] == "cd" {
            assert(len(parts) == 2);
            cd(parts[1]);
        } else {
            $i;
        }
    });
    cd(cwd);
}

fn new(@ref config: dictionary) {
    let name, build, install, uninstall = (
        input("Enter package name (must match the directory name): "),
        input("Enter build commands in a list syntax i.e., [\"cd build\", \"make -j12\"]: "),
        input("Enter install commands in a list syntax i.e., [\"cd build\", \"sudo make install\"]: "),
        input("Enter uninstall commands in a list syntax i.e., [\"cd build\", \"sudo make uninstall\"]: "),
    );

    config.insert(name, {
        "name": name,
        "install": install,
        "build": build,
        "uninstall": uninstall
    });

    log(f"Added package {name}", colors::Tfc.Green);
}

fn usage() {
    println("Usage: thpm -- <option>");
    println("Options:");
    println("  h, help                - show this message");
    println("  n, new                 - create a new package entry");
    println("  l, ls                  - see installed packages");
    println("  i, install <name(s)>   - install a package");
    println("  u, update [name...]    - update package(s) or leave blank for all");
    println("  c, cmd <name...>       - view commands for package(s)");
    println("     uninstall <name...> - uninstall package(s)");
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
    let configured, installed, ciinstalled, unknown = (
        [], [], [], []
    );

    foreach name in names {
        configured += [name];
    }

    let num = 0;
    foreach path in config["thpm_config"].unwrap()["install_paths"].unwrap() {
        foreach p in sys::ls(path) {
            with strip = io::strip_path(p)
            in if names.contains(strip) {
                installed += [(path, strip)];
                num += 1;
            } else {
                let lowercase = names.map(|s| {
                    let buf = "";
                    foreach c in s { buf += Char::tolower(c); }
                    return buf;
                });

                # Check for case insensitive.
                if lowercase.contains(strip) {
                    ciinstalled += [(path, strip)];
                    num += 1;
                } else {
                    unknown += [(path, strip)];
                }
            }
        }
    }

    if !silent {
        foreach c in configured {
            log(f"Configured: {c}", colors::Tfc.Blue);
        }
        foreach i in installed {
            with path = i[0], strip = i[1]
            in log(f"<*> Installed: ({path}) {strip}", colors::Tfc.Green);
        }
        foreach i in ciinstalled {
            with path = i[0], strip = i[1]
            in log(f"<*> Installed: ({path}) {strip} (case insensitive)", colors::Tfc.Green);
        }
        foreach u in unknown {
            with path = u[0], strip = u[1]
            in log(f"<?> Unknown: ({path}) {strip}", colors::Tfc.Yellow);
        }
        log(f"{num} known installed packages", colors::Tfc.Green);
    }
    return num;
}

fn update(config: dictionary, forced_names: list) {
    let paths = config["thpm_config"].unwrap()["package_paths"].unwrap();
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

                log(f"| local hash: {local_commit}", colors::Tfc.White);
                log(f"| remote hash: {remote_commit}", colors::Tfc.White);
                log(f"| base hash: {base_commit}", colors::Tfc.White);

                if local_commit == remote_commit {
                    log(f"|-- Up to date.", colors::Tfc.Green + colors::Te.Bold);
                    print(colors::Te.Reset);
                } else if local_commit == base_commit {
                    log(f"|<- Behind, pulling changes...", colors::Tfc.Yellow);
                    $f"git pull";
                    log("Done", colors::Tfc.Green);
                    needs_reinstall += [strip];
                } else if remote_commit == base_commit {
                    log(f"|-> Ahead of remote, either restore changes or push.", colors::Tfc.Yellow);
                    println(f"    {f}");
                } else {
                    log(f"|-x Diverged from the remote. Manual intervention needed...", colors::Tfc.Red);
                    println(f"    {f}");
                }
            }
        }
    }

    foreach name in needs_reinstall {
        execute_package(config, name);
    }
}

fn show_cmds(config: dictionary, name: str) {
    if !config.has_key(name) { panic(f"{name} has no rules"); }
    log(f"Rules for {name}", colors::Tfc.Green);
    foreach k, v in config[name].unwrap() {
        println(f"{k} = {v}");
    }
}

@pub fn thpm_main() {
    $format("touch ", Config.Path);
    let config = toml::parse(Config.Path);

    if config.empty() {
        let install_path, package_paths = init();
        create_empty_config(install_path, package_paths);
        exit(0);
    }

    if len(argv()) < 2 { usage(); }

    with A = argv()[1:]
    in if A[0] == "h" || A[0] == "help" {
        usage();
    } else if A[0] == "n" || A[0] == "new" {
        new(config);
    } else if A[0] == "i" || A[0] == "install" {
        if len(A) < 2 { panic("install takes a name(s)"); }
        foreach name in A[1:] {
            execute_package(config, name);
        }
    } else if A[0] == "l" || A[0] == "ls" {
        let _ = show_installed_packages(config, false);
    } else if A[0] == "u" || A[0] == "update" {
        if len(A) > 1 { update(config, A[1:]); }
        else { update(config, []); }
    } else if A[0] == "uninstall" {
        if len(A) < 2 { panic("uninstall takes a name(s)"); }
        foreach name in A[1:] {
            uninstall_package(config, name);
        }
    } else if A[0] == "c" || A[0] == "cmd" {
        if len(A) < 2 { panic("uninstall takes a name(s)"); }
        foreach name in A[1:] {
            show_cmds(config, name);
        }
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

