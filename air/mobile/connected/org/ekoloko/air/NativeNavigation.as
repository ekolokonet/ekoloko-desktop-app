package org.ekoloko.air {
    import flash.net.URLRequest;
    import flash.net.navigateToURL;
    import flash.utils.setTimeout;

    public final class NativeNavigation {
        public static var internalLogin:Boolean = false;
        // HtmlNavigation uses navigateToURL("javascript:...") as a second
        // browser bridge, separately from ExternalInterface. Passing it to
        // macOS launches the default URL handler and takes focus from AIR.
        public static function plan(raw:String):Object {
            if (raw == null || raw.length > 16384 || /[\x00-\x1f\x7f]/.test(raw)) return {kind:"unsupported"};
            var url:String = raw.replace(/^\s+|\s+$/g, "");
            if (/^javascript:/i.test(url)) {
                var script:String = url.substr(url.indexOf(":") + 1).replace(/\s*;\s*void\(0\);?\s*$/, "");
                script = script.replace(/[;\s]+$/, "");
                if (/^(setAds\([01]\)|setTableSpacing\([0-9]+,(true|false|[01])\)|hideFooter\(\))$/.test(script))
                    return {kind:"host-layout"};
                if (/^(window\.)?location\.reload\(\)$/.test(script)) return {kind:"reload"};
                // Translate only the literal popup emitted by HtmlNavigation;
                // no JavaScript is evaluated or sent to an external handler.
                var popup:Array = /^window\.open\('([^'\\]+)','win[0-9]+','[A-Za-z0-9=,]+'\)$/.exec(script);
                if (popup) return webPlan(popup[1]);
                return {kind:"unsupported"};
            }
            return webPlan(url);
        }

        private static function webPlan(url:String):Object {
            if (/\s|\\/.test(url)) return {kind:"unsupported"};
            if (internalLogin) {
                try {
                    var resolved:String = NativeServices.resolve(url);
                    // Only the authored game re-login document. Store, help,
                    // password recovery and unrelated links remain external.
                    if (resolved.split("?")[0] == BuildInfo.ORIGIN + "/ekoloko/login.html")
                        return {kind:"reload"};
                } catch (ignoredLogin:Error) {}
            }
            if (/^https?:\/\/[^\/@]+(?:[\/?#]|$)/i.test(url)) return {kind:"web", url:url};
            if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) {
                try { return {kind:"web", url:NativeServices.resolve(url)}; } catch (ignored:Error) {}
            }
            return {kind:"unsupported"};
        }

        public static function open(request:URLRequest, target:String = null):void {
            var action:Object = plan(request ? request.url : null);
            if (action.kind == "host-layout") {
                NativeServices.report({stage:"navigation",reasonCode:"legacy_page_layout_ignored"});
            } else if (action.kind == "reload") {
                if (NativeServices.reload != null) setTimeout(NativeServices.reload, 0);
            } else if (action.kind == "web") {
                var outgoing:URLRequest = new URLRequest(action.url);
                outgoing.method = request.method;
                outgoing.data = request.data;
                outgoing.contentType = request.contentType;
                outgoing.requestHeaders = request.requestHeaders;
                NativeServices.report({stage:"navigation",reasonCode:"external_web_link_opened"});
                navigateToURL(outgoing, target);
            } else {
                NativeServices.report({stage:"navigation",reasonCode:"legacy_navigation_unsupported"});
            }
        }
    }
}
