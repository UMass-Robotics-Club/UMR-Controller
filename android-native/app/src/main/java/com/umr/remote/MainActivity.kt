package com.umr.remote

import android.os.Bundle
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val remoteWebView = findViewById<WebView>(R.id.remoteWebView)

        remoteWebView.settings.javaScriptEnabled = true
        remoteWebView.settings.domStorageEnabled = true
        remoteWebView.settings.allowFileAccess = true
        remoteWebView.settings.allowContentAccess = true
        remoteWebView.webViewClient = WebViewClient()
        remoteWebView.webChromeClient = WebChromeClient()
        remoteWebView.loadUrl("file:///android_asset/index.html")
    }
}
