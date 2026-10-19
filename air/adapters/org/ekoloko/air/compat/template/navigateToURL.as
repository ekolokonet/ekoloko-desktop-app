package org.ekoloko.air.compat.template {
    import flash.net.URLRequest;

    public function navigateToURL(request:URLRequest, window:String = null):void {
        if (Bridge.active) Bridge.api.navigate(request, window);
    }
}
