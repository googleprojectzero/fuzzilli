#!/bin/sh

# set clang as compiler
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

# Make Qt
./configure -skip qt3d,qt5compact,qtactiveqt,qtcharts,qtcoap,qtconnectivity,qtdatavis3d,qtdoc,qtimageformates,qtlanguageserver,qtlottie,qtmqtt,qtmultimedia,qtnetworkauth,qtopcua,qtpositioning,qtquick3d,qtquicktimeline,qtremoteobjects,qtscxml,qtsensors,qtserialbus,qtserialport,qtshadertools,qtsvg,qttools,qttranslations,qtvirtualkeyboard,qtwayland,qtwebchannel,qtwebengine,qtwebsockets,qtwebview -force-debug-info -developer-build
cmake --build . --parallel -- DCMAKE_CXX_FLAGS='fsanitize-coverage=trace-pc-guard -03 -lrt'

# Make harness
cd qtdeclarative/examples/qml/shell
cmake .  && cmake --build . --parallel

echo 'build complete!'
