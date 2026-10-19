package {
 import flash.geom.Rectangle;
 public final class ConnectedDockLayout {
  public static function calculate(safe:Rectangle,left:Array,right:Array):Object {
   var size:Number=48,gap:Number=8,slots:Object={},all:Array=left.concat(right),count:int=all.length;
   var leftWidth:Number=left.length?left.length*size+(left.length-1)*gap:0;
   var rightWidth:Number=right.length?right.length*size+(right.length-1)*gap:0;
   var inline:Boolean=safe.width-leftWidth-rightWidth-gap*2>=260;
   var chat:Rectangle,toolbar:Rectangle,i:int;
   if(inline){
    toolbar=new Rectangle(safe.x,safe.bottom-size,safe.width,size);
    for(i=0;i<left.length;i++)slots[left[i]]=new Rectangle(safe.x+i*(size+gap),toolbar.y,size,size);
    for(i=0;i<right.length;i++)slots[right[i]]=new Rectangle(safe.right-rightWidth+i*(size+gap),toolbar.y,size,size);
    chat=new Rectangle(safe.x+leftWidth+gap,toolbar.y,safe.width-leftWidth-rightWidth-gap*2,size);
   }else{
    var columns:int=Math.max(1,Math.min(count,Math.floor((safe.width+gap)/(size+gap))));
    var rows:int=Math.ceil(count/columns),dockHeight:Number=rows*(size+gap)-gap;
    toolbar=new Rectangle(safe.x,safe.bottom-dockHeight-size-gap,safe.width,dockHeight+size+gap);
    chat=new Rectangle(safe.x,toolbar.y,safe.width,size);
    for(i=0;i<count;i++){
     var row:int=int(i/columns),inRow:int=Math.min(columns,count-row*columns),rowWidth:Number=inRow*size+(inRow-1)*gap;
     slots[all[i]]=new Rectangle(safe.x+(safe.width-rowWidth)/2+(i%columns)*(size+gap),chat.bottom+gap+row*(size+gap),size,size);
    }
   }
   return {slots:slots,chat:chat,toolbar:toolbar};
  }
 }
}
