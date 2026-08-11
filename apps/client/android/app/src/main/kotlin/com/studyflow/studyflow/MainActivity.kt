package com.studyflow.studyflow

import com.studyflow.app.StudyFlowPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StudyFlowPlatform.register(flutterEngine, applicationContext)
    }
}
