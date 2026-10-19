package com.vtweens.components.website.server_selector
{
   import com.vtweens.consts.VERSION;
   import com.vtweens.util.DataProviderLoader;
   import com.vtweens.util.DisplayObjectContainerUtils;
   import com.vtweens.util.LanguageDef;
   import com.vtweens.util.Log;
   import fl.data.DataProvider;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.SimpleButton;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.MouseEvent;
   import flash.text.TextField;
   import org.ekoloko.air.compat.a24cc64e419bb9ef3685c150b.Security;
   
   public class ServerSelector extends MovieClip
   {
      
      public static const DATA_LOADED:String = "data_loaded";
      
      public static const DATA_LOAD_ERROR:String = "data_error";
      
      public static var language:String = LanguageDef.HEBREW;
      
      public var cloud1:MovieClip;
      
      public var title_en:MovieClip;
      
      public var cloud2:MovieClip;
      
      public var cloud3:MovieClip;
      
      public var prevBut:SimpleButton;
      
      public var nextBut:SimpleButton;
      
      public var noNewbiePop:MovieClip;
      
      public var premiumPopup:MovieClip;
      
      public var holder:MovieClip;
      
      public var countText:TextField;
      
      public var title_iw:MovieClip;
      
      public var newbiesPop:MovieClip;
      
      public var title_fr:MovieClip;
      
      public var texts:DataProvider = new DataProvider();
      
      private var caller:*;
      
      private var username:String;
      
      private var isPremium:Boolean = false;
      
      private var isMod:Boolean = false;
      
      private var isNewbie:Boolean = false;
      
      private var isRanger:Boolean = false;
      
      private var slots:Array = [];
      
      private var pages:Array = [];
      
      private var currPage:int = 0;
      
      private var firstTime:int = 0;
      
      private var lastChannelData:ChannelData;
      
      private var textLoader:DataProviderLoader;
      
      private var serversLoader:ServersDataLoader;
      
      private var active:Boolean = false;
      
      private var terminal:Boolean = false;
      
      private var lastFailureReasonValue:String = null;
      
      private var lastHttpStatusValue:int = 0;
      
      private var lastDurationMsValue:int = 0;
      
      public function ServerSelector()
      {
         super();
         addFrameScript(0,frame1,53,frame54);
         Security.allowDomain("*");
         Security.allowInsecureDomain("*");
         firstTime = int(this.root.loaderInfo.parameters.firstTime);
         addEventListener(Event.ADDED_TO_STAGE,clipAddedToStage,false,0,true);
         newbiesPop.visible = false;
         noNewbiePop.visible = false;
         premiumPopup.visible = false;
      }
      
      // Presentation pagination; the existing slot instances retain selection/availability.
      private var mobilePageCapacity:int = 0;
      public function setMobilePageCapacity(capacity:int):void
      {
         capacity = Math.max(1,capacity);
         if(slots.length == 0 || capacity == mobilePageCapacity) return;
         var first:DisplayObject = pages.length && pages[currPage].numChildren ? pages[currPage].getChildAt(0) : null;
         var anchor:int = Math.max(0,slots.indexOf(first));
         if(pages.length && pages[currPage].parent == holder) holder.removeChild(pages[currPage]);
         pages = [];
         for(var i:int = 0; i < slots.length; i++)
         {
            if(i % capacity == 0) pages.push(new Sprite());
            Sprite(pages[pages.length-1]).addChild(slots[i]);
         }
         mobilePageCapacity = capacity;
         currPage = int(anchor / capacity);
         holder.addChild(pages[currPage]);
         countText.text = "" + (currPage + 1);
      }
      public function get mobilePageCount() : int { return pages.length; }
      public function get mobileCurrentPage() : int { return currPage + 1; }

      public function get lastFailureReason() : String
      {
         return lastFailureReasonValue;
      }
      
      public function get lastHttpStatus() : int
      {
         return lastHttpStatusValue;
      }
      
      public function get lastDurationMs() : int
      {
         return lastDurationMsValue;
      }
      
      public function getLanguage() : String
      {
         return language;
      }
      
      public function init(param1:*, param2:*, param3:*, param4:*, param5:*, param6:*) : void
      {
         caller = param1;
         username = param2 == null ? "" : String(param2);
         isPremium = Boolean(param3);
         isMod = Boolean(param4);
         isNewbie = Boolean(param5);
         isRanger = Boolean(param6);
         language = String(param1.getLanguage());
         active = true;
         terminal = false;
         slots = [];
         pages = [];
         currPage = 0;
         lastFailureReasonValue = null;
         lastHttpStatusValue = 0;
         lastDurationMsValue = 0;
         if(language == LanguageDef.HEBREW)
         {
            nextBut.addEventListener(MouseEvent.CLICK,onPrev,false,0,true);
            prevBut.addEventListener(MouseEvent.CLICK,onNext,false,0,true);
         }
         else
         {
            nextBut.addEventListener(MouseEvent.CLICK,onNext,false,0,true);
            prevBut.addEventListener(MouseEvent.CLICK,onPrev,false,0,true);
         }
         configureTitles();
         textLoader = new DataProviderLoader();
         textLoader.addEventListener(Event.COMPLETE,textLoaded,false,0,true);
         textLoader.addEventListener(IOErrorEvent.IO_ERROR,textNotLoaded,false,0,true);
         textLoader.loadXML("./website/common/server_selector/server_selector_text_" + language + ".xml?version=" + VERSION.version);
         serversLoader = new ServersDataLoader();
         serversLoader.addEventListener(ServersDataLoader.DATA_LOADED,serverDataLoaded,false,0,true);
         serversLoader.addEventListener(ServersDataLoader.DATA_LOAD_ERROR,serverDataFailed,false,0,true);
         serversLoader.loadServersData(language);
      }
      
      public function deactivate() : void
      {
         if(!active && terminal)
         {
            return;
         }
         active = false;
         terminal = true;
         removeEventListener(Event.ADDED_TO_STAGE,clipAddedToStage);
         removeEventListener(Event.ENTER_FRAME,cloudMove);
         nextBut.removeEventListener(MouseEvent.CLICK,onNext);
         nextBut.removeEventListener(MouseEvent.CLICK,onPrev);
         prevBut.removeEventListener(MouseEvent.CLICK,onNext);
         prevBut.removeEventListener(MouseEvent.CLICK,onPrev);
         premiumPopup.ok.removeEventListener(MouseEvent.CLICK,closePopup);
         newbiesPop.yesbut.removeEventListener(MouseEvent.CLICK,gotonewbiechannel);
         newbiesPop.nobut.removeEventListener(MouseEvent.CLICK,gotoselectedchannel);
         noNewbiePop.yesbut.removeEventListener(MouseEvent.CLICK,closeNoNewbiePop);
         if(textLoader != null)
         {
            textLoader.removeEventListener(Event.COMPLETE,textLoaded);
            textLoader.removeEventListener(IOErrorEvent.IO_ERROR,textNotLoaded);
            textLoader.dispose();
            textLoader = null;
         }
         if(serversLoader != null)
         {
            serversLoader.removeEventListener(ServersDataLoader.DATA_LOADED,serverDataLoaded);
            serversLoader.removeEventListener(ServersDataLoader.DATA_LOAD_ERROR,serverDataFailed);
            serversLoader.dispose();
            serversLoader = null;
         }
         var slot:ServerChannelSlot = null;
         for each(slot in slots)
         {
            if(slot != null)
            {
               slot.deactivate();
            }
         }
         slots = [];
         pages = [];
         caller = null;
         DisplayObjectContainerUtils.stopAndRemoveHierarchy(this);
      }
      
      public function showPremiumPopup() : void
      {
         if(active)
         {
            premiumPopup.visible = true;
         }
      }
      
      public function isChannelUnavailable(param1:ChannelData) : Boolean
      {
         if(param1 == null || !param1.available || param1.serverData == null || !param1.serverData.healthKnown)
         {
            return true;
         }
         try
         {
            return caller != null && caller.isServerEndpointUnavailable is Function && Boolean(caller.isServerEndpointUnavailable(param1.serverData.getIp(),param1.serverData.getPort()));
         }
         catch(error:Error)
         {
            Log.error("ServerSelector session availability check failed: " + error.message);
         }
         return false;
      }
      
      private function configureTitles() : void
      {
         if(language == LanguageDef.HEBREW)
         {
            title_en.visible = false;
            title_fr.visible = false;
            title_iw.gotoAndStop(firstTime + 1);
         }
         else if(language == LanguageDef.ENGLISH || language == LanguageDef.USA)
         {
            title_fr.visible = false;
            title_iw.visible = false;
            title_en.gotoAndStop(firstTime + 1);
         }
         else if(language == LanguageDef.FRENCH)
         {
            title_en.visible = false;
            title_iw.visible = false;
         }
      }
      
      private function clipAddedToStage(param1:Event) : void
      {
         if(!active && caller != null)
         {
            active = true;
         }
         removeEventListener(Event.ADDED_TO_STAGE,clipAddedToStage);
         addEventListener(Event.ENTER_FRAME,cloudMove,false,0,true);
         play();
      }
      
      private function onPrev(param1:MouseEvent) : void
      {
         if(!active || pages.length == 0)
         {
            return;
         }
         if(pages[currPage].parent == holder)
         {
            holder.removeChild(pages[currPage]);
         }
         currPage = (currPage - 1) % pages.length;
         currPage = currPage < 0 ? pages.length - 1 : currPage;
         holder.addChild(pages[currPage]);
         countText.text = "" + (currPage + 1);
      }
      
      private function onNext(param1:MouseEvent) : void
      {
         if(!active || pages.length == 0)
         {
            return;
         }
         if(pages[currPage].parent == holder)
         {
            holder.removeChild(pages[currPage]);
         }
         currPage = (currPage + 1) % pages.length;
         holder.addChild(pages[currPage]);
         countText.text = "" + (currPage + 1);
      }
      
      private function serverDataLoaded(param1:Event) : void
      {
         if(!active || terminal || param1.currentTarget !== serversLoader)
         {
            return;
         }
         serversLoader.removeEventListener(ServersDataLoader.DATA_LOADED,serverDataLoaded);
         serversLoader.removeEventListener(ServersDataLoader.DATA_LOAD_ERROR,serverDataFailed);
         mobilePageCapacity = 0;
         var channels:Array = serversLoader.getChannelsData();
         if(channels == null || channels.length == 0)
         {
            lastFailureReasonValue = "invalid_response";
            finishWithError();
            return;
         }
         var page:Sprite = new Sprite();
         var index:int = 0;
         while(index < channels.length)
         {
            var slot:ServerChannelSlot = serversLoader.bigDisplay ? new ChannelSlotBigMC() : new ChannelSlotMC();
            slot.init(channels[index] as ChannelData,onSlotSelected,index + 1,isPremium,isMod,isNewbie,isRanger,this);
            if(serversLoader.bigDisplay)
            {
               slot.y = 10 + int(index % 4 / 2) * 110;
               slot.x = -75 + int(index % 2) * 255;
            }
            else
            {
               slot.y = -20 + int(index % 12 / 3) * 75;
               slot.x = -115 + int(index % 3) * 195;
            }
            page.addChild(slot);
            slots.push(slot);
            if(serversLoader.bigDisplay && index % 4 == 3 || !serversLoader.bigDisplay && index % 12 == 11)
            {
               pages.push(page);
               page = new Sprite();
            }
            index++;
         }
         if(page.numChildren > 0)
         {
            pages.push(page);
         }
         if(pages.length == 0)
         {
            lastFailureReasonValue = "invalid_response";
            finishWithError();
            return;
         }
         holder.addChild(pages[currPage]);
         countText.text = "" + (currPage + 1);
         terminal = true;
         Log.info("ServerSelector terminal=data_loaded pages=" + pages.length + " channels=" + channels.length);
         dispatchEvent(new Event(DATA_LOADED));
      }
      
      private function serverDataFailed(param1:Event) : void
      {
         if(!active || terminal || param1.currentTarget !== serversLoader)
         {
            return;
         }
         lastFailureReasonValue = serversLoader.lastFailureReason;
         lastHttpStatusValue = serversLoader.lastHttpStatus;
         lastDurationMsValue = serversLoader.lastDurationMs;
         serversLoader.removeEventListener(ServersDataLoader.DATA_LOADED,serverDataLoaded);
         serversLoader.removeEventListener(ServersDataLoader.DATA_LOAD_ERROR,serverDataFailed);
         finishWithError();
      }
      
      private function finishWithError() : void
      {
         if(!active || terminal)
         {
            return;
         }
         terminal = true;
         Log.error("ServerSelector terminal=data_error reason=" + lastFailureReasonValue + " http=" + lastHttpStatusValue + " durationMs=" + lastDurationMsValue);
         dispatchEvent(new Event(DATA_LOAD_ERROR));
      }
      
      private function onSlotSelected(param1:ServerSelectedEvent) : void
      {
         if(!active)
         {
            return;
         }
         lastChannelData = param1.getChannelData();
         if(isChannelUnavailable(lastChannelData))
         {
            Log.info("ServerSelector ignored an unavailable channel selection");
            return;
         }
         if(ServersDataLoader.hasNewbieChannel)
         {
            if(lastChannelData.isNewbie && !(isNewbie || isMod || isRanger))
            {
               noNewbiePop.visible = true;
               return;
            }
            if(!lastChannelData.isNewbie && isNewbie)
            {
               newbiesPop.visible = true;
               return;
            }
         }
         caller.setSFSData(lastChannelData);
      }
      
      private function textLoaded(param1:Event) : void
      {
         if(!active || param1.currentTarget !== textLoader)
         {
            return;
         }
         textLoader.removeEventListener(Event.COMPLETE,textLoaded);
         textLoader.removeEventListener(IOErrorEvent.IO_ERROR,textNotLoaded);
         texts = textLoader.dataProvider;
         setPremiumPopup();
         setNewbiePopup();
         setNoNewbiePopup();
      }
      
      private function textNotLoaded(param1:IOErrorEvent) : void
      {
         if(!active || param1.currentTarget !== textLoader)
         {
            return;
         }
         textLoader.removeEventListener(Event.COMPLETE,textLoaded);
         textLoader.removeEventListener(IOErrorEvent.IO_ERROR,textNotLoaded);
         setPremiumPopup();
         setNewbiePopup();
         setNoNewbiePopup();
      }
      
      private function getText(param1:String) : String
      {
         var index:int = 0;
         while(index < texts.length)
         {
            var item:Object = texts.getItemAt(index);
            if(item.key == param1)
            {
               return item.value;
            }
            index++;
         }
         return param1;
      }
      
      public function setPremiumPopup() : void
      {
         premiumPopup.ok.addEventListener(MouseEvent.CLICK,closePopup,false,0,true);
         premiumPopup.message.text = getText("premium_pop_text");
         premiumPopup.title.text = getText("premiuim_pop_title");
         premiumPopup.oktxt.mouseEnabled = false;
         premiumPopup.oktxt.text = getText("premiuim_pop_store_but");
      }
      
      public function setNewbiePopup() : void
      {
         newbiesPop.yesbut.addEventListener(MouseEvent.CLICK,gotonewbiechannel,false,0,true);
         newbiesPop.nobut.addEventListener(MouseEvent.CLICK,gotoselectedchannel,false,0,true);
         newbiesPop.txt.text = getText("newbie_pop_text");
         newbiesPop.title.text = getText("newbie_pop_title");
         newbiesPop.yestxt.mouseEnabled = newbiesPop.notxt.mouseEnabled = false;
         newbiesPop.yestxt.text = getText("newbie_pop_goto_newbie");
         newbiesPop.notxt.text = getText("newbie_pop_goto_selected");
      }
      
      public function setNoNewbiePopup() : void
      {
         noNewbiePop.yesbut.addEventListener(MouseEvent.CLICK,closeNoNewbiePop,false,0,true);
         noNewbiePop.txt.text = getText("no_newbie_pop_text");
         noNewbiePop.title.text = getText("no_newbie_pop_title");
         noNewbiePop.yestxt.text = getText("no_newbie_pop_close");
         noNewbiePop.yestxt.mouseEnabled = false;
      }
      
      private function gotoselectedchannel(param1:MouseEvent) : void
      {
         if(lastChannelData != null && !isChannelUnavailable(lastChannelData))
         {
            caller.setSFSData(lastChannelData);
         }
      }
      
      private function gotonewbiechannel(param1:MouseEvent) : void
      {
         if(ServersDataLoader.hasNewbieChannel)
         {
            newbiesPop.visible = false;
         }
      }
      
      private function closePopup(param1:MouseEvent) : void
      {
         premiumPopup.visible = false;
      }
      
      private function closeNoNewbiePop(param1:MouseEvent) : void
      {
         noNewbiePop.visible = false;
      }
      
      private function cloudMove(param1:Event) : void
      {
         cloud1.x += 1;
         if(cloud1.x >= 1060)
         {
            cloud1.x = -50;
            cloud1.y = 50 + int(Math.random() * 200);
         }
         cloud2.x += 1.5;
         if(cloud2.x >= 1060)
         {
            cloud2.x = -50;
            cloud2.y = 50 + int(Math.random() * 200);
         }
         cloud3.x += 2;
         if(cloud3.x >= 1060)
         {
            cloud3.x = -50;
            cloud3.y = 50 + int(Math.random() * 200);
         }
      }
      
      internal function frame1() : void
      {
         stop();
      }
      
      internal function frame54() : void
      {
         stop();
      }
   }
}

