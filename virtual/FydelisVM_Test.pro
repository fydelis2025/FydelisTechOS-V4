QT       += core gui
CONFIG   += c++17
DEFINES  += QT_NO_DEPRECATED_WARNINGS

TARGET = FydelisVM_Test
TEMPLATE = app

INCLUDEPATH += $$PWD/src

SOURCES += \
    src/virtual/core/vmcontroller.cpp \
    src/virtual/ui/virtualpanel.cpp \
    src/virtual/ui/main_test.cpp

HEADERS += \
    src/virtual/defs.h \
    src/virtual/core/vmcontroller.h \
    src/virtual/ui/virtualpanel.h

DESTDIR = $$OUT_PWD/bin