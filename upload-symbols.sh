#!/bin/bash

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info.plist -p ios ~/Downloads/appDsyms.zip
Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info.plist -p ios ~/Downloads/appDsyms\ \(1\).zip

Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info-Lite.plist -p ios ~/Downloads/appDsyms.zip
Pods/FirebaseCrashlytics/upload-symbols -gsp OpenDocumentReader/GoogleService-Info-Lite.plist -p ios ~/Downloads/appDsyms\ \(1\).zip
