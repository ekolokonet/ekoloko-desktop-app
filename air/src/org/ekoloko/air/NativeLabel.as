package org.ekoloko.air {
    import flash.display.Sprite;
    import flash.text.engine.ElementFormat;
    import flash.text.engine.FontDescription;
    import flash.text.engine.FontLookup;
    import flash.text.engine.TextBlock;
    import flash.text.engine.TextElement;
    import flash.text.engine.TextLine;

    public class NativeLabel extends Sprite {
        [Embed(source="../../../../../assets/Gan CLM Bold.ttf", fontName="EkolokoGan", embedAsCFF="true", fontWeight="bold")]
        private static const Gan:Class;
        public function NativeLabel(text:String, width:Number, size:Number = 17, color:uint = 0xffffff, align:String = "center"):void {
            mouseEnabled = false; mouseChildren = false;
            var font:FontDescription = new FontDescription("EkolokoGan", "bold");
            font.fontLookup = FontLookup.EMBEDDED_CFF;
            var top:Number = 0;
            for each (var paragraph:String in text.split("\n")) {
                if (!paragraph.length) { top += size * 1.4; continue; }
                var block:TextBlock = new TextBlock(new TextElement(paragraph, new ElementFormat(font, size, color)));
                block.bidiLevel = 1;
                var previous:TextLine = null;
                var line:TextLine;
                while ((line = block.createTextLine(previous, width)) != null) {
                    line.x = Math.round(align == "right" ? width - line.textWidth : align == "left" ? 0 : (width - line.textWidth) / 2);
                    line.y = Math.round(top + size); addChild(line); previous = line; top += size * 1.45;
                }
            }
        }
    }
}
