################################################################################
# CONFIGURE PROJECT MAKEFILE (optional)
#   This file is where we make project specific configurations.
################################################################################

################################################################################
# OF ROOT
#   The location of your root openFrameworks installation
#       (default) OF_ROOT = ../../..
################################################################################
# OF_ROOT = ../../..

################################################################################
# PROJECT ROOT
#   The location of the project - a starting place for searching for files
#       (default) PROJECT_ROOT = . (this directory)
################################################################################
# PROJECT_ROOT = .

################################################################################
# PROJECT CFLAGS
#   C++17 is needed for the inline variables in TrackOSCSkeletons.h and the
#   structured bindings in ofApp.cpp (openFrameworks 0.11+ already uses it).
################################################################################
PROJECT_CFLAGS = -std=c++17
