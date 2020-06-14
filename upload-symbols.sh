#!/bin/bash

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info.plist -p ios ~/Downloads/appDsyms-full.zip

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info-Lite.plist -p ios ~/Downloads/appDsyms-lite.zip
