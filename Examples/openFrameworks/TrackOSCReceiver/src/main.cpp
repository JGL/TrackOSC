#include "ofApp.h"
#include "ofMain.h"

int main() {
    ofGLWindowSettings settings;
    settings.setSize(720, 960);
    settings.windowMode = OF_WINDOW;
    ofCreateWindow(settings);
    ofRunApp(new ofApp());
}
