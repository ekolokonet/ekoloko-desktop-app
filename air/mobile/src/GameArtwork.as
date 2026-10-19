package {
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.geom.Rectangle;
    public final class GameArtwork {
        [Embed(source="../../build/mobile-lab/assets/room.swf",symbol="BGMC")] public static var Background:Class;
        [Embed(source="../../build/mobile-lab/assets/room.swf",symbol="FGMC")] public static var Foreground:Class;
        [Embed(source="../../build/mobile-lab/assets/room.swf",symbol="Walkarea")] public static var Walkarea:Class;
        [Embed(source="../../build/mobile-lab/assets/faces.swf",symbol="Head_1")] private static var Head:Class;
        [Embed(source="../../build/mobile-lab/assets/faces.swf",symbol="Eyes_1")] private static var Eyes:Class;
        [Embed(source="../../build/mobile-lab/assets/hair.swf",symbol="ItemMC")] private static var Hair:Class;
        [Embed(source="../../build/mobile-lab/assets/shadow.swf")] private static var Shadow:Class;
        [Embed(source="../../build/mobile-lab/assets/torso.swf",symbol="ItemMC")] private static var Torso:Class;
        [Embed(source="../../build/mobile-lab/assets/legs.swf",symbol="ItemMC")] private static var Legs:Class;
        [Embed(source="../../build/mobile-lab/assets/leftarm.swf",symbol="ItemMC")] private static var LeftArm:Class;
        [Embed(source="../../build/mobile-lab/assets/rightarm.swf",symbol="ItemMC")] private static var RightArm:Class;
        [Embed(source="../../build/mobile-lab/assets/shirt.swf",symbol="ItemMC")] private static var Shirt:Class;
        [Embed(source="../../build/mobile-lab/assets/leftsleeve.swf",symbol="ItemMC")] private static var LeftSleeve:Class;
        [Embed(source="../../build/mobile-lab/assets/rightsleeve.swf",symbol="ItemMC")] private static var RightSleeve:Class;
        [Embed(source="../../build/mobile-lab/assets/pants.swf",symbol="ItemMC")] private static var Pants:Class;
        [Embed(source="../../build/mobile-lab/assets/shoes.swf",symbol="ItemMC")] private static var Shoes:Class;
        [Embed(source="../../build/mobile-lab/assets/npc.swf",symbol="NpcMC")] public static var Resident:Class;

        public static function avatar():Sprite {
            var avatar:Sprite=new Sprite(),layers:Sprite=new Sprite();layers.name="layers";avatar.addChild(layers);
            // Back-to-front order from the native AvatarLayersHelper northOrder.
            for each(var type:Class in [Shadow,LeftArm,RightArm,Torso,Legs,Shoes,Pants,
                LeftSleeve,RightSleeve,Shirt,Head,Eyes,Hair]) layers.addChild(new type());
            pose(avatar,"s_stand");
            var bounds:Rectangle=layers.getBounds(layers);
            layers.x=-bounds.x-bounds.width/2;layers.y=-bounds.bottom;
            avatar.mouseChildren=false;
            return avatar;
        }
        public static function stopTree(object:DisplayObject):void {
            if(object is MovieClip) MovieClip(object).stop();
            if(object is DisplayObjectContainer) {
                var container:DisplayObjectContainer=object as DisplayObjectContainer;
                for(var i:int=0;i<container.numChildren;i++) stopTree(container.getChildAt(i));
            }
        }
        public static function pose(avatar:Sprite,label:String):void {
            var layers:Sprite=avatar.getChildByName("layers") as Sprite;
            if(!layers)return;
            for(var i:int=0;i<layers.numChildren;i++) {
                var clip:MovieClip=layers.getChildAt(i) as MovieClip;
                if(!clip) continue;
                for each(var item:Object in clip.currentLabels) {
                    if(item.name==label) {clip.gotoAndStop(label);break;}
                }
                stopTree(clip);
                if(label.indexOf("walk")>=0) for(var j:int=0;j<clip.numChildren;j++) {
                    if(clip.getChildAt(j) is MovieClip) MovieClip(clip.getChildAt(j)).play();
                }
            }
        }
    }
}
