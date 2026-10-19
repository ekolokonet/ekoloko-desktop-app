package com.vtweens.dataobjects.recycle.item
{
   import com.vtweens.consts.VERSION;
   import com.vtweens.shell.ItemCache;
   import com.vtweens.util.Log;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IOErrorEvent;
   import flash.net.URLRequest;
   
   public class RecycleItemDisplayData extends EventDispatcher
   {
      
      public static const DATA_LOADED:String = "data_loaded";
      
      private var itemLoader:Loader = new Loader();
      
      private var itemCtor:* = null;
      
      protected var itemData:RecycleItemData = null;
      
      public function RecycleItemDisplayData(param1:int)
      {
         super();
         this.itemData = ItemCache.GetRecycleItemData(param1);
         if(this.isLoaded)
         {
            dispatchEvent(new Event(DATA_LOADED));
         }
         else
         {
            this.loadMC();
         }
      }
      
      public function get type() : int
      {
         return this.itemData.type;
      }
      
      public function get id() : int
      {
         return this.itemData.id;
      }
      
      public function get ordinal() : int
      {
         return this.itemData.ordinal;
      }
      
      public function get price() : *
      {
         return this.itemData.price;
      }
      
      public function get name() : String
      {
         return this.itemData.name;
      }
      
      public function get description() : String
      {
         return this.itemData.description;
      }
      
      public function get inventoryType() : int
      {
         return this.itemData.inventoryType;
      }
      
      public function getItem() : MovieClip
      {
         if(this.itemCtor == null)
         {
            // Missing optional artwork must not abort room/inventory completion.
            // Transparent bounds keep the existing image scalers finite.
            var empty:MovieClip = new MovieClip();
            empty.graphics.beginFill(0,0);
            empty.graphics.drawRect(0,0,1,1);
            empty.graphics.endFill();
            empty.mouseEnabled = false;
            empty.mouseChildren = false;
            return empty;
         }
         return new this.itemCtor();
      }
      
      public function get isLoaded() : Boolean
      {
         return this.itemLoader == null;
      }
      
      protected function getURL() : *
      {
         return "./recycle_items/" + this.itemData.type + "_" + this.ordinal + ".swf" + "?r=" + VERSION.RECYCLE_ITEMS_VERSION;
      }
      
      override public function addEventListener(param1:String, param2:Function, param3:Boolean = false, param4:int = 0, param5:Boolean = false) : void
      {
         super.addEventListener(param1,param2,param3,param4,param5);
         if(param1 == DATA_LOADED && this.isLoaded)
         {
            dispatchEvent(new Event(DATA_LOADED));
         }
      }
      
      private function onItemLoaded(param1:*) : *
      {
         this.itemCtor = param1.target.content.getMC();
         this.itemLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onItemLoaded);
         this.itemLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onItemLoadError);
         this.itemLoader = null;
         dispatchEvent(new Event(DATA_LOADED));
      }
      
      private function onItemLoadError(param1:*) : *
      {
         this.itemLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onItemLoaded);
         this.itemLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onItemLoadError);
         this.itemLoader = null;
         Log.error("While loading recycle item " + this.getURL());
         dispatchEvent(new Event(DATA_LOADED));
      }
      
      private function loadMC() : *
      {
         this.itemLoader.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onItemLoaded);
         this.itemLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onItemLoadError);
         var _loc1_:URLRequest = new URLRequest(this.getURL());
         this.itemLoader.load(_loc1_);
      }
   }
}

