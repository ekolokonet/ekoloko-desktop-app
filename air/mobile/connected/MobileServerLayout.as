package {
 import flash.geom.Rectangle;
 /** Authored left-to-right rows, anchored at the top of the parchment. */
 public final class MobileServerLayout {
  public static function calculate(w:Number,h:Number,count:int,pages:int):Object {
   var gap:Number=12;
   var cover:Number=Math.max(w/960,h/600),offset:Number=(w-960*cover)/2;
   var paperLeft:Number=Math.max(20,offset+200*cover),paperRight:Number=Math.min(w-20,offset+752*cover);
   var width:Number=paperRight-paperLeft-16;
   var footer:Number=64;
   var area:Rectangle=new Rectangle(paperLeft+8,100,width,Math.max(100,h-100-footer));
   // Server count never changes the size or position of existing cards. Keep
   // the original three-column order, reducing columns only on narrow phones.
   var cols:int=Math.min(3,Math.max(1,int((width+gap)/(124+gap))));
   var cardW:Number=Math.min(180,(width-(cols-1)*gap)/cols);
   var cardH:Number=cardW/2.8,rows:int=Math.ceil(count/cols);
   var contentH:Number=Math.max(0,rows*(cardH+gap)-gap),slots:Array=[];
   for(var i:int=0;i<count;i++)slots.push(new Rectangle((i%cols)*(cardW+gap),int(i/cols)*(cardH+gap),cardW,cardH));
   var capacity:int=cols*Math.max(1,int((area.height+gap)/(cardH+gap)));
   return {area:area,slots:slots,capacity:capacity,maxScroll:0,pages:pages};
  }
 }
}
