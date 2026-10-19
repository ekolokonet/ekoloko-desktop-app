package {
    import flash.display.*;
    import flash.geom.*;
    import flash.events.*;
    import flash.accessibility.AccessibilityProperties;
    public final class OriginalUI {
        [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="MainMenuMCStatic")] public static var Menu:Class;
        [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="Questmenu")] public static var QuestPanel:Class;
        [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="TextBox")] public static var Chat:Class;
        [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="PlainBaloon")] public static var Balloon:Class;
        private static var menu:DisplayObjectContainer;
        private static var icons:Object={};
        private static var skins:Object={};
        public static const DOCK:Array=["userSettingsBut","myHouse","myAnimal","emoticons","myData","quests","buddies","map"];
        public static const TITLES:Object={userSettingsBut:"הגדרות",myHouse:"הבית שלי",myAnimal:"החיה שלי",emoticons:"רגשונים",myData:"הדמות שלי",quests:"משימות",buddies:"חברים",map:"מפה",cards:"אלבום קלפים",paperBut:"העיתון",help:"עזרה",pioStore:"חנות חלוצים",muteBut:"צליל",logout:"יציאה"};
        public static function part(o:DisplayObjectContainer,name:String):DisplayObject {
            var item:DisplayObject=o.getChildByName(name);if(!item)throw new Error("Missing original UI member: "+name);return item;
        }
        public static function normalized(o:DisplayObject):Sprite {
            var r:Rectangle=o.getBounds(o);var s:Sprite=new Sprite();s.addChild(o);o.scaleX=o.scaleY=1;o.x=-r.x;o.y=-r.y;return s;
        }
        public static function icon(id:String,action:Function):Sprite {
            if(!menu){menu=new Menu();GameArtwork.stopTree(menu);}
            if(!icons[id]){
                var o:DisplayObject=part(menu,id),c:DisplayObjectContainer=o as DisplayObjectContainer;
                if(c){
                    if(id=="myData"||id=="quests")o=part(c,"up");
                    else if(id=="map")o=part(c,"regular");
                    else if(id=="buddies"||id=="emoticons")o=part(c,"but");
                    else if(id=="myHouse")o=c.getChildAt(0);
                    else if(id=="help"){var mark:MovieClip=part(c,"mark") as MovieClip;mark.gotoAndStop("freeze");GameArtwork.stopTree(mark);}
                }
                icons[id]=o;
            }
            return target(icons[id],48,48,TITLES[id],action);
        }
        public static function target(art:DisplayObject,w:Number,h:Number,title:String,action:Function):Sprite {
            var b:Sprite=new Sprite();b.name=title;b.buttonMode=true;
            var n:Sprite=normalized(art);var s:Number=Math.min((w-2)/n.width,(h-2)/n.height,1.2);
            n.scaleX=n.scaleY=s;n.x=(w-n.width)/2;n.y=(h-n.height)/2;b.addChild(n);
            b.graphics.beginFill(0,0);b.graphics.drawRect(0,0,w,h);b.graphics.endFill();
            b.accessibilityProperties=new AccessibilityProperties();b.accessibilityProperties.name=title;
            b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{e.stopPropagation();action();});
            b.addEventListener(MouseEvent.MOUSE_DOWN,function(e:MouseEvent):void{e.stopPropagation();b.alpha=.75;});
            b.addEventListener(MouseEvent.MOUSE_UP,function(e:MouseEvent):void{b.alpha=1;});
            b.addEventListener(MouseEvent.MOUSE_OUT,function(e:MouseEvent):void{b.alpha=1;});
            return b;
        }
        // All skins below are original vector symbols; only their layout changes.
        public static function chatBackground(w:Number,h:Number,source:DisplayObject=null):Sprite {
            var c:DisplayObjectContainer=new Chat();GameArtwork.stopTree(c);
            return stretch(source?"live-chat":"chat",source||c.getChildAt(0),w,h,18,64);
        }
        public static function panelBackground(w:Number,h:Number):Sprite {
            var c:DisplayObjectContainer=new QuestPanel();GameArtwork.stopTree(c);
            var bg:DisplayObjectContainer=c.getChildAt(1) as DisplayObjectContainer;
            return stretch("panel",bg.getChildAt(0),w,h,24);
        }
        private static function stretch(key:String,art:DisplayObject,w:Number,h:Number,edge:Number,rightEdge:Number=NaN):Sprite {
            // Rasterize the original vectors at 2x once, then nine-slice without
            // distorting corners. ADL's mobile profile rejects nested scale9Grid.
            if(!skins[key]){
                var r:Rectangle=art.getBounds(art),bw:int=Math.ceil(r.width*2),bh:int=Math.ceil(r.height*2);
                var pixels:BitmapData=new BitmapData(bw,bh,true,0);
                pixels.draw(art,new Matrix(2,0,0,2,-r.x*2,-r.y*2));
                var ex:int=Math.min(edge*2,int(bw/3)),ey:int=Math.min(edge*2,int(bh/3));
                var er:int=isNaN(rightEdge)?ex:Math.min(rightEdge*2,int(bw/3));
                var xs:Array=[0,ex,bw-er,bw],ys:Array=[0,ey,bh-ey,bh],parts:Array=[];
                for(var row:int=0;row<3;row++)for(var col:int=0;col<3;col++){
                    var rect:Rectangle=new Rectangle(xs[col],ys[row],xs[col+1]-xs[col],ys[row+1]-ys[row]);
                    var slice:BitmapData=new BitmapData(rect.width,rect.height,true,0);slice.copyPixels(pixels,rect,new Point());parts.push(slice);
                }
                pixels.dispose();skins[key]={parts:parts,ex:ex/2,er:er/2,ey:ey/2};
            }
            var data:Object=skins[key];var dx:Number=Math.min(data.ex,w/3),dy:Number=Math.min(data.ey,h/3);
            var dr:Number=Math.min(data.er,w/3);
            var xx:Array=[0,dx,w-dr,w],yy:Array=[0,dy,h-dy,h];var s:Sprite=new Sprite();
            for(row=0;row<3;row++)for(col=0;col<3;col++){
                var bitmap:Bitmap=new Bitmap(data.parts[row*3+col],"auto",true);bitmap.x=xx[col];bitmap.y=yy[row];
                bitmap.width=xx[col+1]-xx[col];bitmap.height=yy[row+1]-yy[row];s.addChild(bitmap);
            }
            s.mouseEnabled=false;s.mouseChildren=false;return s;
        }
        public static function closeButton(action:Function):Sprite {
            return actionButton("close",action);
        }
        public static const ACTION_NAMES:Object={overview:"הצגת כל החדר",follow:"חזרה לדמות שלי",rotate:"סיבוב התצוגה",opacity:"שינוי שקיפות",zoomIn:"התקרבות",zoomOut:"התרחקות",messages:"הודעות אחרונות",close:"סגירה",hideKeyboard:"הסתרת המקלדת",older:"הודעות קודמות",newer:"מעבר להודעה האחרונה"};
        public static function actionButton(id:String,action:Function):Sprite {
            var art:DisplayObject=MobileActionArt.make(id);
            var button:Sprite=target(art,48,48,ACTION_NAMES[id],action);button.name="action-"+id;
            button.accessibilityProperties.description=ACTION_NAMES[id];return button;
        }
        public static function submit(action:Function):Sprite {
            var c:DisplayObjectContainer=new Chat();GameArtwork.stopTree(c);
            return target(part(c,"submitBut"),44,44,"שליחה",action);
        }
        public static function speechBackground(w:Number,h:Number):Sprite {
            var c:DisplayObjectContainer=new Balloon();GameArtwork.stopTree(c);
            var txt:DisplayObject=c.getChildByName("txt");if(txt)c.removeChild(txt);
            var s:Sprite=normalized(c);s.width=w;s.height=h;return s;
        }
        public static function dump(o:DisplayObject,depth:int=0):void {
            trace("UI_TREE "+depth+" "+o.name+" "+o+" "+o.getBounds(o)+" at="+o.x+","+o.y);
            if(depth<2&&o is DisplayObjectContainer){var c:DisplayObjectContainer=DisplayObjectContainer(o);for(var i:int=0;i<c.numChildren;i++)dump(c.getChildAt(i),depth+1);}
        }
    }
}
