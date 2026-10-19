package {
    import flash.display.DisplayObject;
    public final class MobileActionArt {
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Overview")] private static var Overview:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Follow")] private static var Follow:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Rotate")] private static var Rotate:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Opacity")] private static var Opacity:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="ZoomIn")] private static var ZoomIn:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="ZoomOut")] private static var ZoomOut:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Older")] private static var Older:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Newer")] private static var Newer:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Close")] private static var Close:Class;
        [Embed(source="../assets/icons/MobileActionIcons.swf",symbol="Messages")] private static var Messages:Class;
        public static const IDS:Array=["overview","follow","rotate","opacity","zoomIn","zoomOut","older","newer","close","messages"];
        public static function make(id:String):DisplayObject {
            var types:Object={overview:Overview,follow:Follow,rotate:Rotate,opacity:Opacity,zoomIn:ZoomIn,zoomOut:ZoomOut,older:Older,newer:Newer,hideKeyboard:Newer,close:Close,messages:Messages};
            if(!types[id])throw new Error("Missing mobile action artwork: "+id);
            var cls:Class=types[id];return new cls() as DisplayObject;
        }
    }
}
