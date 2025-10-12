# Target: Qt QJSEngine


To build the Qt QJSEngine for fuzzing:

1. clone the repo: `git clone git://code.qt.io/qt/qt5.git qt6` (the qt5 repo contains the code for both qt5 and qt6 in different branches)
2. clone submodules:
`cd qt6 && perl init-repository`
2. Apply Patches/\* from within the qtdeclarative/ submodule. The patches should apply cleanly to the git revision specified in [./REVISION](./REVISION)
3. Run fuzzbuild.sh in the qt6 root directory
4. fuzzing harness will be located at qt6/qtdeclarative/examples/qml/shell/shell
