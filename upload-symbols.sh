#!/bin/bash

TODAY=$(date '+%Y-%m-%d')

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info.plist -p ios ~/Library/Developer/Xcode/Archives/$TODAY/OpenDocumentReader\ Full*.xcarchive/dSYMs/

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info-Lite.plist -p ios ~/Library/Developer/Xcode/Archives/$TODAY/OpenDocumentReader\ Lite*.xcarchive/dSYMs/
