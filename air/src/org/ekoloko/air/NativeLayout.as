package org.ekoloko.air {
    public final class NativeLayout {
        public static function calculate(width:Number, height:Number, fullscreen:Boolean):Object {
            var outer:Number = Math.min(width / 960, height / 600);
            var bar:Number = fullscreen ? 0 : Math.min(92, height / 4);
            var fit:Number = Math.min(width / 960, (height - bar) / 600);
            return {left:(960 - width / outer) / 2, top:(600 - height / outer) / 2,
                width:width / outer, height:height / outer, bar:bar / outer, outerScale:outer, barPoints:bar,
                gameScale:fit / outer, gameX:(960 - 960 * fit / outer) / 2,
                gameY:(600 - height / outer) / 2 + (bar + (height - bar - 600 * fit) / 2) / outer};
        }
    }
}
