#!/bin/bash

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

TODAY=$(date '+%Y-%m-%d')

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info.plist -p ios ~/Library/Developer/Xcode/Archives/$TODAY/OpenDocumentReader\ Full*.xcarchive/dSYMs/

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info-Lite.plist -p ios ~/Library/Developer/Xcode/Archives/$TODAY/OpenDocumentReader\ Lite*.xcarchive/dSYMs/

