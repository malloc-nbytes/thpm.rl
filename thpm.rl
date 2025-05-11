[thpm_config]
install_paths = [/usr/local/bin]
package_paths = [/home/zdh/Software]
[gf]
clone = ["git clone https://github.com/nakst/gf.git"]
uninstall = ["sudo rm /usr/local/bin/gf"]
build = ["./build.sh"]
install = ["sudo cp ./gf2 /usr/local/bin/gf"]
name = gf
installed = true
[gitcheck]
clone = ["git clone https://www.github.com/malloc-nbytes/gitcheck.git"]
uninstall = ["sudo rm /usr/local/bin/gitcheck"]
build = ["cd src", "make -j12"]
install = ["cd src", "sudo cp ./gitcheck /usr/local/bin"]
name = gitcheck
installed = true
[EARL]
build = ["mkdir build", "cd build", "cmake ..", "make -j12"]
install = ["cd build", "sudo make install"]
name = EARL
uninstall = ["cd build", "sudo make uninstall"]
clone = ["git clone https://www.github.com/malloc-nbytes/EARL.git/"]
installed = true
[bless]
clone = ["git clone https://www.github.com/malloc-nbytes/bless.git"]
uninstall = ["cd build", "sudo make uninstall"]
build = ["mkdir build", "cd build", "cmake ..", "make -j12"]
install = ["cd build", "sudo make install"]
name = bless
installed = true
[ampire]
build = ["mkdir build", "cd build", "cmake ..", "make -j12"]
install = ["cd build", "sudo make install"]
name = ampire
uninstall = ["cd build", "sudo make uninstall"]
clone = ["git clone --recursive https://www.github.com/malloc-nbytes/ampire.git"]
installed = true
[thpm.rl]
installed = true
build = []
install = ["sudo cp ./thpm.rl /usr/local/bin/"]
name = thpm.rl
uninstall = ["sudo rm /usr/local/bin/thpm.rl"]
clone = ["git clone https://github.com/malloc-nbytes/thpm.rl.git"]
[EARL-language-support]
installed = true
build = ["cd vscode", "vsce package"]
install = ["cd emacs", "cp ./earl-mode.el ~/.emacs.d/lisp/", "cd ../vim/", "cp ./earl.vim ~/.vim/syntax"]
name = EARL-language-support
uninstall = []
clone = ["git clone https://github.com/malloc-nbytes/EARL-language-support.git"]
[bm]
clone = ["git clone https://www.github.com/malloc-nbytes/bm.git"]
uninstall = ["cd build", "sudo make uninstall"]
build = ["mkdir build", "cd build", "cmake ..", "make -j12"]
install = ["cd build", "sudo make install"]
name = bm
installed = true
[far]
clone = ["git clone https://www.github.com/malloc-nbytes/far.git"]
uninstall = ["sudo rm /usr/local/bin/far.py"]
build = []
install = ["sudo cp ./src/far.py /usr/local/bin"]
name = far
installed = true
[.thpm]
installed = true
build = []
install = ["mv ./.thpm ~/.thpm"]
name = .thpm
uninstall = ["rm ~/.thpm"]
clone = ["git clone https://github.com/malloc-nbytes/.thpm.git"]
