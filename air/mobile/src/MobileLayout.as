package {
    import flash.geom.Rectangle;
    public final class MobileLayout {
        /** Screen bounds and safeArea share native screen units, independent of
         * SHOW_ALL and Retina density. Read only on layout, never per frame. */
        public static function safeInsets(width:Number,height:Number,screen:Rectangle,safe:Rectangle,fallback:Object):Object {
            if(!screen||!safe||screen.isEmpty()||safe.isEmpty())return fallback;
            // A stale pre-rotation rectangle must not be mapped onto the new axes.
            if((screen.width>screen.height)!=(width>height))return {left:64,right:64,top:fallback.top,bottom:fallback.bottom};
            var sx:Number=width/screen.width,sy:Number=height/screen.height;
            return {left:Math.max(fallback.left,(safe.left-screen.left)*sx+4),right:Math.max(fallback.right,(screen.right-safe.right)*sx+4),
                top:Math.max(fallback.top,(safe.top-screen.top)*sy+4),bottom:Math.max(fallback.bottom,(screen.bottom-safe.bottom)*sy+4)};
        }
        public static function calculate(width:Number,height:Number,insets:Object,
                                         keyboard:Rectangle=null,editing:Boolean=false):Object {
            var portrait:Boolean=height>width;
            var safe:Rectangle=new Rectangle(insets.left,insets.top,width-insets.left-insets.right,height-insets.top-insets.bottom);
            var bottom:Number=safe.bottom;
            if(keyboard && keyboard.height>0 && keyboard.intersects(safe))bottom=Math.min(bottom,keyboard.y);
            var compact:Boolean=editing&&keyboard&&keyboard.height>0&&keyboard.intersects(safe);
            var composerHeight:Number=compact?36:46;
            var composer:Rectangle=new Rectangle(safe.x+4,bottom-composerHeight-(compact?2:4),safe.width-8,composerHeight);
            var stacked:Boolean=safe.width<600;
            var dockHeight:Number=stacked?156:48;
            var toolbar:Rectangle=new Rectangle(safe.x,safe.bottom-dockHeight,safe.width,dockHeight);
            // The real HUD overlays the room; it never owns an opaque footer.
            var viewBottom:Number=keyboard&&keyboard.height>0&&keyboard.intersects(safe)?bottom:height;
            var feed:Rectangle=new Rectangle(safe.x,76,Math.min(350,safe.width),Math.min(244,viewBottom-76));
            return {safe:safe,portrait:portrait,stacked:stacked,viewport:new Rectangle(0,0,width,Math.max(80,viewBottom)),
                composer:composer,compactComposer:compact,feed:feed,toolbar:toolbar,
                chat:new Rectangle(stacked?safe.x:safe.x+196,safe.bottom-48,stacked?safe.width:safe.width-392,44),
                joystickX:safe.x+76,joystickY:(editing?composer.y:toolbar.y)-80};
        }
    }
}
