package it.gotoandplay.smartfoxserver
{
   import com.adobe.serialization.json.JSON;
   import ek2.EK2Config;
   import ek2.EK2Crypto;
   import ek2.EK2Session;
   import flash.events.ErrorEvent;
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.TimerEvent;
   import flash.external.ExternalInterface;
   import flash.net.FileReference;
   import flash.net.Socket;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.system.Security;
   import flash.utils.ByteArray;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   import it.gotoandplay.smartfoxserver.data.Room;
   import it.gotoandplay.smartfoxserver.data.User;
   import it.gotoandplay.smartfoxserver.handlers.ExtHandler;
   import it.gotoandplay.smartfoxserver.handlers.IMessageHandler;
   import it.gotoandplay.smartfoxserver.handlers.SysHandler;
   import it.gotoandplay.smartfoxserver.http.HttpConnection;
   import it.gotoandplay.smartfoxserver.http.HttpEvent;
   import it.gotoandplay.smartfoxserver.util.Entities;
   import it.gotoandplay.smartfoxserver.util.ObjectSerializer;
   
   public class SmartFoxClient extends EventDispatcher
   {
      
      private static const EOM:int = 0;
      
      private static const MSG_XML:String = "<";
      
      private static const MSG_JSON:String = "{";
      
      private static var MSG_STR:String = "%";
      
      private static var MIN_POLL_SPEED:Number = 0;
      
      private static var DEFAULT_POLL_SPEED:Number = 750;
      
      private static var MAX_POLL_SPEED:Number = 10000;
      
      private static var HTTP_POLL_REQUEST:String = "poll";
      
      public static const MODMSG_TO_USER:String = "u";
      
      public static const MODMSG_TO_ROOM:String = "r";
      
      public static const MODMSG_TO_ZONE:String = "z";
      
      public static const XTMSG_TYPE_XML:String = "xml";
      
      public static const XTMSG_TYPE_STR:String = "str";
      
      public static const XTMSG_TYPE_JSON:String = "json";
      
      public static const CONNECTION_MODE_DISCONNECTED:String = "disconnected";
      
      public static const CONNECTION_MODE_SOCKET:String = "socket";
      
      public static const CONNECTION_MODE_HTTP:String = "http";
      
      public static const EK2_STATE_DISCONNECTED:String = EK2Session.DISCONNECTED;
      
      public static const EK2_STATE_HANDSHAKING:String = EK2Session.HANDSHAKING;
      
      public static const EK2_STATE_READY:String = EK2Session.READY;
      
      public static const EK2_STATE_FAILED:String = EK2Session.FAILED;
      
      private var roomList:Array;
      
      private var connected:Boolean;
      
      private var benchStartTime:int;
      
      private var sysHandler:SysHandler;
      
      private var extHandler:ExtHandler;
      
      private var majVersion:Number;
      
      private var minVersion:Number;
      
      private var subVersion:Number;
      
      private var messageHandlers:Array;
      
      private var socketConnection:Socket;
      
      private var byteBuffer:ByteArray;

      // Yield between bounded receive slices, retaining unread bytes in Socket.
      // A single authenticated record/callback remains atomic and may exceed this budget.
      private static const RECEIVE_BUDGET_MS:int = 4;
      private static const RECEIVE_BYTE_LIMIT:int = 65536;
      private static const RECEIVE_RECORD_LIMIT:int = 32;
      private var receiveTimer:Timer;
      private var pendingReceiveSocket:Socket;
      
      private var ek2Session:EK2Session;
      
      private var ek2State:String = EK2_STATE_DISCONNECTED;
      
      private var ek2ClientHello:String;
      
      private var initialLoginAttemptId:String;
      
      private var currentLoginAttemptIdValue:String;
      
      private var loginFlowIdValue:String;
      
      private var entropyLoader:URLLoader;
      
      private var handshakeTimer:Timer;
      
      private var partialRecordTimer:Timer;
      
      private var inactivityTimer:Timer;
      
      private var ek2HandshakePhase:String = "CLOSED";
      
      private var pendingHost:String;
      
      private var pendingPort:int;
      
      private var physicalSocketConnected:Boolean = false;
      
      private var ek2FallbackHost:String;
      
      private var ek2FallbackPort:int = 0;
      
      private var ek2FallbackAttempted:Boolean = false;
      
      private var loginTelemetryReporter:Function;
      
      private var cardsStaticRequestObserved:Boolean = false;
      
      private var staticDataRequestObserved:Boolean = false;
      
      private var inventoryRequestObserved:Boolean = false;
      
      private var cardsStaticTerminalObserved:Boolean = false;
      
      private var staticDataTerminalObserved:Boolean = false;
      
      private var inventoryTerminalObserved:Boolean = false;
      
      private var heartbeatPending:Boolean = false;
      
      private var heartbeatNonce:Number = -1;
      
      private var heartbeatLastNonce:Number = -1;
      
      private var heartbeatRecentNonces:Array = [];
      
      private var heartbeatConsecutiveMisses:int = 0;
      
      private var heartbeatFailureReported:Boolean = false;
      
      private var autoConnectOnConfigSuccess:Boolean = false;
      
      public var ipAddress:String;
      
      public var port:int = 9339;
      
      public var defaultZone:String;
      
      private var isHttpMode:Boolean = false;
      
      private var _httpPollSpeed:int = DEFAULT_POLL_SPEED;
      
      private var httpConnection:HttpConnection;
      
      public var blueBoxIpAddress:String;
      
      public var blueBoxPort:Number = 0;
      
      public var smartConnect:Boolean = false;
      
      public var buddyList:Array;
      
      public var myBuddyVars:Array;
      
      public var debug:Boolean;
      
      public var myUserId:int;
      
      public var myUserName:String;
      
      public var playerId:int;
      
      public var amIModerator:Boolean;
      
      private var _activeRoomId:int;
      
      public var changingRoom:Boolean;
      
      public var httpPort:int = 8080;
      
      public var properties:Object = null;
      
      public var bubbleCannonAuthorityAckGateVersion:int;
      
      internal var ignore:* = false;
      
      public function SmartFoxClient(param1:Boolean = false)
      {
         super();
         this.bubbleCannonAuthorityAckGateVersion = 3;
         this.majVersion = 1;
         this.minVersion = 5;
         this.subVersion = 6;
         this.activeRoomId = -1;
         this.debug = param1;
         this.messageHandlers = [];
         this.setupMessageHandlers();
         this.replaceSocketConnection();
         this.httpConnection = new HttpConnection();
         this.httpConnection.addEventListener(HttpEvent.onHttpConnect,this.handleHttpConnect);
         this.httpConnection.addEventListener(HttpEvent.onHttpClose,this.handleHttpClose);
         this.httpConnection.addEventListener(HttpEvent.onHttpData,this.handleHttpData);
         this.httpConnection.addEventListener(HttpEvent.onHttpError,this.handleHttpError);
         this.byteBuffer = new ByteArray();
         this.handshakeTimer = new Timer(EK2Config.ENTROPY_TIMEOUT_MS,1);
         this.handshakeTimer.addEventListener(TimerEvent.TIMER_COMPLETE,this.handleHandshakeTimeout);
         this.partialRecordTimer = new Timer(EK2Config.PARTIAL_RECORD_TIMEOUT_MS,1);
         this.partialRecordTimer.addEventListener(TimerEvent.TIMER_COMPLETE,this.handlePartialRecordTimeout);
         this.receiveTimer = new Timer(8,1);
         this.receiveTimer.addEventListener(TimerEvent.TIMER_COMPLETE,this.resumeSocketData);
         this.inactivityTimer = new Timer(EK2Config.INACTIVITY_TIMEOUT_MS,1);
         this.inactivityTimer.addEventListener(TimerEvent.TIMER_COMPLETE,this.handleInactivityTimeout);
      }
      
      private static function isCanonicalUuidV4(param1:String) : Boolean
      {
         return param1 != null && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(param1);
      }
      
      public function get activeRoomId() : int
      {
         return this._activeRoomId;
      }
      
      public function set activeRoomId(param1:int) : void
      {
         this._activeRoomId = param1;
         this.reportPresenceRoom(param1);
      }
      
      private function reportPresenceRoom(param1:int) : void
      {
         var _loc2_:Room = null;
         try
         {
            if(param1 > 0 && ExternalInterface.available)
            {
               _loc2_ = this.roomList[param1] as Room;
               ExternalInterface.call("ekolokoPresence",this.myUserName != null ? this.myUserName : "",_loc2_ != null ? _loc2_.getName() : "");
            }
         }
         catch(e:Error)
         {
         }
      }
      
      public function get rawProtocolSeparator() : String
      {
         return MSG_STR;
      }
      
      public function set rawProtocolSeparator(param1:String) : void
      {
         if(param1 != "<" && param1 != "{")
         {
            MSG_STR = param1;
         }
      }
      
      public function get isConnected() : Boolean
      {
         return this.connected;
      }
      
      public function set isConnected(param1:Boolean) : void
      {
         this.connected = param1;
      }
      
      public function get httpPollSpeed() : int
      {
         return this._httpPollSpeed;
      }
      
      public function set httpPollSpeed(param1:int) : void
      {
         if(param1 >= 0 && param1 <= 10000)
         {
            this._httpPollSpeed = param1;
         }
      }
      
      public function loadConfig(param1:String = "config.xml", param2:Boolean = true) : void
      {
         this.autoConnectOnConfigSuccess = param2;
         var _loc3_:URLLoader = new URLLoader();
         _loc3_.addEventListener(Event.COMPLETE,this.onConfigLoadSuccess);
         _loc3_.addEventListener(IOErrorEvent.IO_ERROR,this.onConfigLoadFailure);
         _loc3_.load(new URLRequest(param1));
      }
      
      public function getConnectionMode() : String
      {
         var _loc1_:String = CONNECTION_MODE_DISCONNECTED;
         if(this.isConnected)
         {
            if(this.isHttpMode)
            {
               _loc1_ = CONNECTION_MODE_HTTP;
            }
            else
            {
               _loc1_ = CONNECTION_MODE_SOCKET;
            }
         }
         return _loc1_;
      }
      
      public function connect(param1:String, param2:int = 9339) : void
      {
         if(!this.connected && (this.ek2State == EK2_STATE_DISCONNECTED || this.ek2State == EK2_STATE_FAILED))
         {
            this.initialize();
            this.currentLoginAttemptIdValue = null;
            this.ipAddress = param1;
            this.port = param2;
            this.ek2FallbackAttempted = false;
            this.beginEncryptedEndpointAttempt(param1,param2);
         }
         else
         {
            this.debugMessage("*** ALREADY CONNECTED OR CONNECTING ***");
         }
      }
      
      public function setEncryptedFallbackEndpoint(param1:String, param2:int) : void
      {
         var _loc3_:String = param1 == null ? "" : param1.replace(/^\s+|\s+$/g,"");
         if(_loc3_.length == 0 || _loc3_.indexOf("/") >= 0 || _loc3_.indexOf("\\") >= 0 || param2 < 1 || param2 > 65535)
         {
            this.ek2FallbackHost = null;
            this.ek2FallbackPort = 0;
            return;
         }
         this.ek2FallbackHost = _loc3_;
         this.ek2FallbackPort = param2;
      }
      
      public function setInitialLoginCorrelation(param1:String, param2:String) : void
      {
         if(!isCanonicalUuidV4(param1) || !isCanonicalUuidV4(param2) || this.ek2State != EK2_STATE_DISCONNECTED)
         {
            throw new Error("Invalid initial login correlation");
         }
         this.initialLoginAttemptId = param1;
         this.loginFlowIdValue = param2;
      }
      
      public function setLoginFlowCorrelation(param1:String) : void
      {
         if(!isCanonicalUuidV4(param1) || this.ek2State != EK2_STATE_DISCONNECTED)
         {
            throw new Error("Invalid login flow correlation");
         }
         this.initialLoginAttemptId = null;
         this.loginFlowIdValue = param1;
      }
      
      public function get loginAttemptId() : String
      {
         return this.currentLoginAttemptIdValue == null ? this.initialLoginAttemptId : this.currentLoginAttemptIdValue;
      }
      
      public function get loginFlowId() : String
      {
         return this.loginFlowIdValue;
      }
      
      public function setLoginTelemetryReporter(param1:Function) : void
      {
         this.loginTelemetryReporter = param1;
      }
      
      private function emitLoginTelemetry(param1:String, param2:Object = null) : *
      {
         if(this.loginTelemetryReporter == null)
         {
            return null;
         }
         try
         {
            return this.loginTelemetryReporter(param1,param2 == null ? {} : param2);
         }
         catch(param3:Error)
         {
            this.debugMessage("[LOGIN-TELEMETRY] reporter rejected event");
         }
         return null;
      }
      
      private function resetLoginResponseTracking() : void
      {
         this.cardsStaticRequestObserved = false;
         this.staticDataRequestObserved = false;
         this.inventoryRequestObserved = false;
         this.cardsStaticTerminalObserved = false;
         this.staticDataTerminalObserved = false;
         this.inventoryTerminalObserved = false;
         this.heartbeatPending = false;
         this.heartbeatNonce = -1;
         this.heartbeatLastNonce = -1;
         this.heartbeatRecentNonces = [];
         this.heartbeatConsecutiveMisses = 0;
         this.heartbeatFailureReported = false;
      }
      
      private function beforeJsonExtensionRequest(param1:String, param2:String, param3:*) : Boolean
      {
         if(param1 == "95" && param2 == "95" && !this.cardsStaticRequestObserved)
         {
            this.cardsStaticRequestObserved = true;
            this.emitLoginTelemetry("cards_static_requested",{"cacheStatus":"miss"});
         }
         else if(param1 == "36" && param2 == "36")
         {
            if(!this.cardsStaticRequestObserved && !this.cardsStaticTerminalObserved)
            {
               this.cardsStaticTerminalObserved = true;
               this.emitLoginTelemetry("cards_static_cache_hit",{"cacheStatus":"hit"});
            }
            if(!this.staticDataRequestObserved)
            {
               this.staticDataRequestObserved = true;
               this.emitLoginTelemetry("static_data_requested",{"cacheStatus":"miss"});
            }
         }
         else if(param1 == "3" && param2 == "38")
         {
            if(!this.cardsStaticRequestObserved && !this.cardsStaticTerminalObserved)
            {
               this.cardsStaticTerminalObserved = true;
               this.emitLoginTelemetry("cards_static_cache_hit",{"cacheStatus":"hit"});
            }
            if(!this.staticDataRequestObserved && !this.staticDataTerminalObserved)
            {
               this.staticDataTerminalObserved = true;
               this.emitLoginTelemetry("static_data_cache_hit",{"cacheStatus":"hit"});
            }
            if(!this.inventoryRequestObserved)
            {
               this.inventoryRequestObserved = true;
               this.emitLoginTelemetry("inventory_requested",{"cacheStatus":"unknown"});
            }
         }
         if(param1 == "82" && param2 == "82")
         {
            if(this.ignore)
            {
               this.heartbeatPending = false;
               this.heartbeatNonce = -1;
               this.heartbeatRecentNonces = [];
               this.heartbeatConsecutiveMisses = 0;
               this.heartbeatFailureReported = false;
               return true;
            }
            if(param3 == null || typeof param3 != "object")
            {
               return false;
            }
            if(this.heartbeatPending)
            {
               ++this.heartbeatConsecutiveMisses;
               if(this.heartbeatConsecutiveMisses == 1)
               {
                  this.emitLoginTelemetry("server_response_degraded",{
                     "assetName":"heartbeat",
                     "failureReason":"timeout"
                  });
               }
               if(this.heartbeatConsecutiveMisses >= 3)
               {
                  if(!this.heartbeatFailureReported)
                  {
                     this.heartbeatFailureReported = true;
                     this.emitLoginTelemetry("server_response_timeout",{
                        "assetName":"heartbeat",
                        "failureReason":"timeout"
                     });
                  }
                  this.heartbeatPending = false;
                  return false;
               }
               this.heartbeatRecentNonces.push(this.heartbeatNonce);
               while(this.heartbeatRecentNonces.length > 3)
               {
                  this.heartbeatRecentNonces.shift();
               }
            }
            var _loc4_:Number = Number(uint(getTimer()) % 2147483647);
            if(_loc4_ == this.heartbeatLastNonce)
            {
               _loc4_ = (_loc4_ + 1) % 2147483647;
            }
            this.heartbeatLastNonce = _loc4_;
            this.heartbeatNonce = _loc4_;
            this.heartbeatPending = true;
            param3["110"] = _loc4_;
         }
         return true;
      }
      
      private function inspectJsonExtensionResponse(param1:Object) : Boolean
      {
         if(param1 == null || param1.o == null || typeof param1.o != "object")
         {
            return false;
         }
         var _loc2_:Object = param1.o;
         var _loc3_:String = _loc2_["21"] == null ? "" : String(_loc2_["21"]);
         if(_loc3_ == "523" && this.cardsStaticRequestObserved && !this.cardsStaticTerminalObserved)
         {
            this.cardsStaticTerminalObserved = true;
            if(this.emitLoginTelemetry("extension_response",{
               "command":"523",
               "usable":this.usableCardsStaticResponse(_loc2_)
            }) === false)
            {
               return true;
            }
         }
         else if(_loc3_ == "244" && this.staticDataRequestObserved && !this.staticDataTerminalObserved)
         {
            this.staticDataTerminalObserved = true;
            if(this.emitLoginTelemetry("extension_response",{
               "command":"244",
               "usable":this.usableStaticDataResponse(_loc2_)
            }) === false)
            {
               return true;
            }
         }
         else if((_loc3_ == "121" || _loc3_ == "123") && this.inventoryRequestObserved && !this.inventoryTerminalObserved)
         {
            this.inventoryTerminalObserved = true;
            if(this.emitLoginTelemetry("extension_response",{
               "command":_loc3_,
               "usable":_loc3_ == "121" && _loc2_["122"] is Array
            }) === false)
            {
               return true;
            }
         }
         if(_loc3_ != "140")
         {
            return false;
         }
         var _loc4_:Boolean = this.hasExactHeartbeatKeys(_loc2_) && typeof _loc2_["110"] == "number" && Boolean(isFinite(Number(_loc2_["110"]))) && typeof _loc2_["111"] == "number" && Boolean(isFinite(Number(_loc2_["111"]))) && typeof _loc2_["112"] == "number" && Boolean(isFinite(Number(_loc2_["112"])));
         if(!this.heartbeatPending)
         {
            return _loc4_;
         }
         if(!_loc4_)
         {
            if(_loc2_.hasOwnProperty("110") && typeof _loc2_["110"] == "number" && Number(_loc2_["110"]) == this.heartbeatNonce)
            {
               this.heartbeatPending = false;
               if(!this.heartbeatFailureReported)
               {
                  this.heartbeatFailureReported = true;
                  this.emitLoginTelemetry("server_response_invalid",{
                     "assetName":"heartbeat",
                     "failureReason":"invalid_response"
                  });
               }
               return true;
            }
            return false;
         }
         var _loc5_:Number = Number(_loc2_["110"]);
         if(_loc5_ != this.heartbeatNonce)
         {
            if(this.heartbeatRecentNonces.indexOf(_loc5_) >= 0)
            {
               return true;
            }
            this.heartbeatPending = false;
            if(!this.heartbeatFailureReported)
            {
               this.heartbeatFailureReported = true;
               this.emitLoginTelemetry("server_response_invalid",{
                  "assetName":"heartbeat",
                  "failureReason":"invalid_response"
               });
            }
            return true;
         }
         this.heartbeatPending = false;
         if(this.heartbeatConsecutiveMisses > 0)
         {
            this.emitLoginTelemetry("server_response_recovered",{"assetName":"heartbeat"});
         }
         this.heartbeatConsecutiveMisses = 0;
         this.heartbeatRecentNonces = [];
         this.heartbeatFailureReported = false;
         return true;
      }
      
      private function hasExactHeartbeatKeys(param1:Object) : Boolean
      {
         var _loc2_:int = 0;
         var _loc3_:String = null;
         for(_loc3_ in param1)
         {
            if(_loc3_ != "21" && _loc3_ != "110" && _loc3_ != "111" && _loc3_ != "112")
            {
               return false;
            }
            _loc2_++;
         }
         return _loc2_ == 4 && String(param1["21"]) == "140";
      }
      
      private function usableCardsStaticResponse(param1:Object) : Boolean
      {
         return param1 != null && param1["448"] is Array && param1["465"] is Array && param1["514"] is Array && param1["522"] is Array;
      }
      
      private function usableStaticDataResponse(param1:Object) : Boolean
      {
         if(param1 == null)
         {
            return false;
         }
         var _loc2_:Array = ["52","58","59","60","61","164","243","289","335","559","621","622","623","631"];
         var _loc3_:String = null;
         for each(_loc3_ in _loc2_)
         {
            if(!(param1[_loc3_] is Array))
            {
               return false;
            }
         }
         return true;
      }
      
      public function disconnect() : void
      {
         this.connected = false;
         this.resetPhysicalCryptoState();
         this.sysHandler.dispatchDisconnection();
      }
      
      public function addBuddy(param1:String) : void
      {
         var _loc2_:* = null;
         if(param1 != this.myUserName && !this.checkBuddyDuplicates(param1))
         {
            _loc2_ = "<n>" + param1 + "</n>";
            this.send({"t":"sys"},"addB",-1,_loc2_);
         }
      }
      
      public function autoJoin() : void
      {
         if(!this.checkRoomList())
         {
            return;
         }
         var _loc1_:Object = {"t":"sys"};
         this.send(_loc1_,"autoJoin",this.activeRoomId ? this.activeRoomId : -1,"");
      }
      
      public function clearBuddyList() : void
      {
         this.buddyList = [];
         this.send({"t":"sys"},"clearB",-1,"");
         var _loc1_:Object = {};
         _loc1_.list = this.buddyList;
         var _loc2_:SFSEvent = new SFSEvent(SFSEvent.onBuddyList,_loc1_);
         dispatchEvent(_loc2_);
      }
      
      public function createRoom(param1:Object, param2:int = -1) : void
      {
         var _loc10_:String = null;
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param2 == -1)
         {
            param2 = this.activeRoomId;
         }
         var _loc3_:Object = {"t":"sys"};
         var _loc4_:String = param1.isGame ? "1" : "0";
         var _loc5_:String = "1";
         var _loc6_:String = param1.maxUsers == null ? "0" : String(param1.maxUsers);
         var _loc7_:String = param1.maxSpectators == null ? "0" : String(param1.maxSpectators);
         var _loc8_:String = param1.joinAsSpectator ? "1" : "0";
         if(Boolean(param1.isGame) && param1.exitCurrentRoom != null)
         {
            _loc5_ = param1.exitCurrentRoom ? "1" : "0";
         }
         var _loc9_:* = "<room tmp=\'1\' gam=\'" + _loc4_ + "\' spec=\'" + _loc7_ + "\' exit=\'" + _loc5_ + "\' jas=\'" + _loc8_ + "\'>";
         _loc9_ += "<name><![CDATA[" + (param1.name == null ? "" : param1.name) + "]]></name>";
         _loc9_ += "<pwd><![CDATA[" + (param1.password == null ? "" : param1.password) + "]]></pwd>";
         _loc9_ += "<max>" + _loc6_ + "</max>";
         if(param1.uCount != null)
         {
            _loc9_ += "<uCnt>" + (param1.uCount ? "1" : "0") + "</uCnt>";
         }
         if(param1.extension != null)
         {
            _loc9_ += "<xt n=\'" + param1.extension.name;
            _loc9_ += "\' s=\'" + param1.extension.script + "\' />";
         }
         if(param1.vars == null)
         {
            _loc9_ += "<vars></vars>";
         }
         else
         {
            _loc9_ += "<vars>";
            for(_loc10_ in param1.vars)
            {
               _loc9_ += this.getXmlRoomVariable(param1.vars[_loc10_]);
            }
            _loc9_ += "</vars>";
         }
         _loc9_ += "</room>";
         this.send(_loc3_,"createRoom",param2,_loc9_);
      }
      
      public function getAllRooms() : Array
      {
         return this.roomList;
      }
      
      public function getBuddyByName(param1:String) : Object
      {
         var _loc2_:Object = null;
         for each(_loc2_ in this.buddyList)
         {
            if(_loc2_.name == param1)
            {
               return _loc2_;
            }
         }
         return null;
      }
      
      public function getBuddyById(param1:int) : Object
      {
         var _loc2_:Object = null;
         for each(_loc2_ in this.buddyList)
         {
            if(_loc2_.id == param1)
            {
               return _loc2_;
            }
         }
         return null;
      }
      
      public function getBuddyRoom(param1:Object) : void
      {
         if(param1.id != -1)
         {
            this.send({"t":"sys"},"roomB",-1,"<b id=\'" + param1.id + "\' />");
         }
      }
      
      public function getRoom(param1:int) : Room
      {
         if(!this.checkRoomList())
         {
            return null;
         }
         return this.roomList[param1];
      }
      
      public function getRoomByName(param1:String) : Room
      {
         var _loc3_:Room = null;
         if(!this.checkRoomList())
         {
            return null;
         }
         var _loc2_:Room = null;
         for each(_loc3_ in this.roomList)
         {
            if(_loc3_.getName() == param1)
            {
               _loc2_ = _loc3_;
               break;
            }
         }
         return _loc2_;
      }
      
      public function getRoomList() : void
      {
         var _loc1_:Object = {"t":"sys"};
         this.send(_loc1_,"getRmList",this.activeRoomId,"");
      }
      
      public function getActiveRoom() : Room
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return null;
         }
         return this.roomList[this.activeRoomId];
      }
      
      public function getRandomKey() : void
      {
         this.send({"t":"sys"},"rndK",-1,"");
      }
      
      public function getUploadPath() : String
      {
         return "http://" + this.ipAddress + ":" + this.httpPort + "/default/uploads/";
      }
      
      public function getVersion() : String
      {
         return this.majVersion + "." + this.minVersion + "." + this.subVersion;
      }
      
      public function joinRoom(param1:*, param2:String = "", param3:Boolean = false, param4:Boolean = false, param5:int = -1) : void
      {
         var _loc8_:Room = null;
         var _loc9_:Object = null;
         var _loc10_:String = null;
         var _loc11_:int = 0;
         var _loc12_:* = null;
         if(!this.checkRoomList())
         {
            return;
         }
         var _loc6_:int = -1;
         var _loc7_:int = param3 ? 1 : 0;
         if(!this.changingRoom)
         {
            if(typeof param1 == "number")
            {
               _loc6_ = int(param1);
            }
            else if(typeof param1 == "string")
            {
               for each(_loc8_ in this.roomList)
               {
                  if(_loc8_.getName() == param1)
                  {
                     _loc6_ = _loc8_.getId();
                     break;
                  }
               }
            }
            if(_loc6_ != -1)
            {
               _loc9_ = {"t":"sys"};
               _loc10_ = param4 ? "0" : "1";
               _loc11_ = param5 > -1 ? param5 : this.activeRoomId;
               if(this.activeRoomId == -1)
               {
                  _loc10_ = "0";
                  _loc11_ = -1;
               }
               _loc12_ = "<room id=\'" + _loc6_ + "\' pwd=\'" + param2 + "\' spec=\'" + _loc7_ + "\' leave=\'" + _loc10_ + "\' old=\'" + _loc11_ + "\' />";
               this.send(_loc9_,"joinRoom",this.activeRoomId,_loc12_);
               this.changingRoom = true;
            }
            else
            {
               this.debugMessage("SmartFoxError: requested room to join does not exist!");
            }
         }
      }
      
      public function leaveRoom(param1:int) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         var _loc2_:Object = {"t":"sys"};
         var _loc3_:* = "<rm id=\'" + param1 + "\' />";
         this.send(_loc2_,"leaveRoom",param1,_loc3_);
      }
      
      public function loadBuddyList() : void
      {
         this.send({"t":"sys"},"loadB",-1,"");
      }
      
      public function login(param1:String, param2:String, param3:String) : void
      {
         var _loc4_:Object = {"t":"sys"};
         this.myUserName = param2;
         var _loc5_:* = "<login z=\'" + param1 + "\'><nick><![CDATA[" + param2 + "]]></nick><pword><![CDATA[" + param3 + "]]></pword></login>";
         this.send(_loc4_,"login",0,_loc5_);
      }
      
      public function logout() : void
      {
         var _loc1_:Object = {"t":"sys"};
         this.send(_loc1_,"logout",-1,"");
      }
      
      public function removeBuddy(param1:String) : void
      {
         var _loc3_:Object = null;
         var _loc4_:String = null;
         var _loc5_:Object = null;
         var _loc6_:* = null;
         var _loc7_:Object = null;
         var _loc8_:SFSEvent = null;
         var _loc2_:Boolean = false;
         for(_loc4_ in this.buddyList)
         {
            _loc3_ = this.buddyList[_loc4_];
            if(_loc3_.name == param1)
            {
               delete this.buddyList[_loc4_];
               _loc2_ = true;
               break;
            }
         }
         if(_loc2_)
         {
            _loc5_ = {"t":"sys"};
            _loc6_ = "<n>" + param1 + "</n>";
            this.send(_loc5_,"remB",-1,_loc6_);
            _loc7_ = {};
            _loc7_.list = this.buddyList;
            _loc8_ = new SFSEvent(SFSEvent.onBuddyList,_loc7_);
            dispatchEvent(_loc8_);
         }
      }
      
      public function roundTripBench() : void
      {
         this.benchStartTime = getTimer();
         this.send({"t":"sys"},"roundTrip",this.activeRoomId,"");
      }
      
      public function sendBuddyPermissionResponse(param1:Boolean, param2:String) : void
      {
         var _loc3_:Object = {"t":"sys"};
         var _loc4_:* = "<n res=\'" + (param1 ? "g" : "r") + "\'>" + param2 + "</n>";
         this.send(_loc3_,"bPrm",-1,_loc4_);
      }
      
      public function sendPublicMessage(param1:String, param2:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param2 == -1)
         {
            param2 = this.activeRoomId;
         }
         var _loc3_:Object = {"t":"sys"};
         var _loc4_:* = "<txt><![CDATA[" + Entities.encodeEntities(param1) + "]]></txt>";
         this.send(_loc3_,"pubMsg",param2,_loc4_);
      }
      
      public function sendPrivateMessage(param1:String, param2:int, param3:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param3 == -1)
         {
            param3 = this.activeRoomId;
         }
         var _loc4_:Object = {"t":"sys"};
         var _loc5_:* = "<txt rcp=\'" + param2 + "\'><![CDATA[" + Entities.encodeEntities(param1) + "]]></txt>";
         this.send(_loc4_,"prvMsg",param3,_loc5_);
      }
      
      public function sendModeratorMessage(param1:String, param2:String, param3:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         var _loc4_:Object = {"t":"sys"};
         var _loc5_:* = "<txt t=\'" + param2 + "\' id=\'" + param3 + "\'><![CDATA[" + Entities.encodeEntities(param1) + "]]></txt>";
         this.send(_loc4_,"modMsg",this.activeRoomId,_loc5_);
      }
      
      public function sendObject(param1:Object, param2:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param2 == -1)
         {
            param2 = this.activeRoomId;
         }
         var _loc3_:* = "<![CDATA[" + ObjectSerializer.getInstance().serialize(param1) + "]]>";
         var _loc4_:Object = {"t":"sys"};
         this.send(_loc4_,"asObj",param2,_loc3_);
      }
      
      public function sendObjectToGroup(param1:Object, param2:Array, param3:int = -1) : void
      {
         var _loc5_:String = null;
         var _loc6_:Object = null;
         var _loc7_:* = null;
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param3 == -1)
         {
            param3 = this.activeRoomId;
         }
         var _loc4_:String = "";
         for(_loc5_ in param2)
         {
            if(!isNaN(param2[_loc5_]))
            {
               _loc4_ += param2[_loc5_] + ",";
            }
         }
         _loc4_ = _loc4_.substr(0,_loc4_.length - 1);
         param1._$$_ = _loc4_;
         _loc6_ = {"t":"sys"};
         _loc7_ = "<![CDATA[" + ObjectSerializer.getInstance().serialize(param1) + "]]>";
         this.send(_loc6_,"asObjG",param3,_loc7_);
      }
      
      public function sendXtMessage(param1:String, param2:String, param3:*, param4:String = "xml", param5:int = -1) : void
      {
         var _loc6_:Object = null;
         var _loc7_:Object = null;
         var _loc8_:* = null;
         var _loc9_:String = null;
         var _loc10_:Number = Number(NaN);
         var _loc11_:Object = null;
         var _loc12_:Object = null;
         var _loc13_:String = null;
         if(!this.checkRoomList())
         {
            return;
         }
         if(param5 == -1)
         {
            param5 = this.activeRoomId;
         }
         if(param4 == XTMSG_TYPE_JSON && !this.beforeJsonExtensionRequest(param1,param2,param3))
         {
            return;
         }
         if(param4 == XTMSG_TYPE_XML)
         {
            _loc6_ = {"t":"xt"};
            _loc7_ = {
               "name":param1,
               "cmd":param2,
               "param":param3
            };
            _loc8_ = "<![CDATA[" + ObjectSerializer.getInstance().serialize(_loc7_) + "]]>";
            this.send(_loc6_,"xtReq",param5,_loc8_);
         }
         else if(param4 == XTMSG_TYPE_STR)
         {
            _loc9_ = MSG_STR + "xt" + MSG_STR + param1 + MSG_STR + param2 + MSG_STR + param5 + MSG_STR;
            _loc10_ = 0;
            while(_loc10_ < param3.length)
            {
               _loc9_ += param3[_loc10_].toString() + MSG_STR;
               _loc10_++;
            }
            this.sendString(_loc9_);
         }
         else if(param4 == XTMSG_TYPE_JSON)
         {
            _loc11_ = {};
            _loc11_.x = param1;
            _loc11_.c = param2;
            _loc11_.r = param5;
            _loc11_.p = param3;
            _loc12_ = {};
            _loc12_.t = "xt";
            _loc12_.b = _loc11_;
            _loc13_ = com.adobe.serialization.json.JSON.encode(_loc12_);
            this.sendJson(_loc13_);
         }
      }
      
      public function setBuddyBlockStatus(param1:String, param2:Boolean) : void
      {
         var _loc4_:* = null;
         var _loc5_:Object = null;
         var _loc6_:SFSEvent = null;
         var _loc3_:Object = this.getBuddyByName(param1);
         if(_loc3_ != null)
         {
            if(_loc3_.isBlocked != param2)
            {
               _loc3_.isBlocked = param2;
               _loc4_ = "<n x=\'" + (param2 ? "1" : "0") + "\'>" + param1 + "</n>";
               this.send({"t":"sys"},"setB",-1,_loc4_);
               _loc5_ = {};
               _loc5_.buddy = _loc3_;
               _loc6_ = new SFSEvent(SFSEvent.onBuddyListUpdate,_loc5_);
               dispatchEvent(_loc6_);
            }
         }
      }
      
      public function setBuddyVariables(param1:Array) : void
      {
         var _loc4_:String = null;
         var _loc5_:String = null;
         var _loc2_:Object = {"t":"sys"};
         var _loc3_:* = "<vars>";
         for(_loc4_ in param1)
         {
            _loc5_ = param1[_loc4_];
            if(this.myBuddyVars[_loc4_] != _loc5_)
            {
               this.myBuddyVars[_loc4_] = _loc5_;
               _loc3_ += "<var n=\'" + _loc4_ + "\'><![CDATA[" + _loc5_ + "]]></var>";
            }
         }
         _loc3_ += "</vars>";
         this.send(_loc2_,"setBvars",-1,_loc3_);
      }
      
      public function setRoomVariables(param1:Array, param2:int = -1, param3:Boolean = true) : void
      {
         var _loc5_:* = null;
         var _loc6_:Object = null;
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param2 == -1)
         {
            param2 = this.activeRoomId;
         }
         var _loc4_:Object = {"t":"sys"};
         if(param3)
         {
            _loc5_ = "<vars>";
         }
         else
         {
            _loc5_ = "<vars so=\'0\'>";
         }
         for each(_loc6_ in param1)
         {
            _loc5_ += this.getXmlRoomVariable(_loc6_);
         }
         _loc5_ += "</vars>";
         this.send(_loc4_,"setRvars",param2,_loc5_);
      }
      
      public function setUserVariables(param1:Object, param2:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param2 == -1)
         {
            param2 = this.activeRoomId;
         }
         var _loc3_:Object = {"t":"sys"};
         var _loc4_:Room = this.getActiveRoom();
         var _loc5_:User = _loc4_.getUser(this.myUserId);
         _loc5_.setVariables(param1);
         var _loc6_:String = this.getXmlUserVariable(param1);
         this.send(_loc3_,"setUvars",param2,_loc6_);
      }
      
      public function switchSpectator(param1:int = -1) : void
      {
         if(!this.checkRoomList() || !this.checkJoin())
         {
            return;
         }
         if(param1 == -1)
         {
            param1 = this.activeRoomId;
         }
         this.send({"t":"sys"},"swSpec",param1,"");
      }
      
      public function uploadFile(param1:FileReference, param2:int = -1, param3:String = "", param4:int = -1) : void
      {
         if(param2 == -1)
         {
            param2 = this.myUserId;
         }
         if(param3 == "")
         {
            param3 = this.myUserName;
         }
         if(param4 == -1)
         {
            param4 = this.httpPort;
         }
         param1.upload(new URLRequest("http://" + this.ipAddress + ":" + param4 + "/default/Upload.py?id=" + param2 + "&nick=" + param3));
         this.debugMessage("[UPLOAD]: http://" + this.ipAddress + ":" + param4 + "/default/Upload.py?id=" + param2 + "&nick=" + param3);
      }
      
      public function __logout() : void
      {
         this.initialize(true);
      }
      
      public function sendString(param1:String) : void
      {
         this.debugMessage("[Sending - STR]: encrypted payload, len=" + param1.length);
         this.writeToSocket(param1);
      }
      
      public function sendJson(param1:String) : void
      {
         this.debugMessage("[Sending - JSON]: encrypted payload, len=" + param1.length);
         this.writeToSocket(param1);
      }
      
      public function getBenchStartTime() : int
      {
         return this.benchStartTime;
      }
      
      public function clearRoomList() : void
      {
         this.roomList = [];
      }
      
      private function initialize(param1:Boolean = false) : void
      {
         this.changingRoom = false;
         this.amIModerator = false;
         this.playerId = -1;
         this.activeRoomId = -1;
         this.myUserId = -1;
         this.myUserName = "";
         this.roomList = [];
         this.buddyList = [];
         this.myBuddyVars = [];
         if(!param1)
         {
            this.connected = false;
            this.isHttpMode = false;
            this.resetPhysicalCryptoState();
         }
      }
      
      private function onConfigLoadSuccess(param1:Event) : void
      {
         var _loc4_:SFSEvent = null;
         var _loc2_:URLLoader = param1.target as URLLoader;
         var _loc3_:XML = new XML(_loc2_.data);
         this.ipAddress = this.blueBoxIpAddress = _loc3_.ip;
         this.port = int(_loc3_.port);
         this.defaultZone = _loc3_.zone;
         if(_loc3_.blueBoxIpAddress != undefined)
         {
            this.blueBoxIpAddress = _loc3_.blueBoxIpAddress;
         }
         if(_loc3_.blueBoxPort != undefined)
         {
            this.blueBoxPort = _loc3_.blueBoxPort;
         }
         if(_loc3_.debug != undefined)
         {
            this.debug = _loc3_.debug.toLowerCase() == "true" ? true : false;
         }
         if(_loc3_.smartConnect != undefined)
         {
            this.smartConnect = false;
         }
         if(_loc3_.httpPort != undefined)
         {
            this.httpPort = int(_loc3_.httpPort);
         }
         if(_loc3_.httpPollSpeed != undefined)
         {
            this.httpPollSpeed = int(_loc3_.httpPollSpeed);
         }
         if(_loc3_.rawProtocolSeparator != undefined)
         {
            this.rawProtocolSeparator = _loc3_.rawProtocolSeparator;
         }
         if(this.autoConnectOnConfigSuccess)
         {
            this.connect(this.ipAddress,this.port);
         }
         else
         {
            _loc4_ = new SFSEvent(SFSEvent.onConfigLoadSuccess,{});
            dispatchEvent(_loc4_);
         }
      }
      
      private function onConfigLoadFailure(param1:IOErrorEvent) : void
      {
         var _loc2_:Object = {"message":param1.text};
         var _loc3_:SFSEvent = new SFSEvent(SFSEvent.onConfigLoadFailure,_loc2_);
         dispatchEvent(_loc3_);
      }
      
      private function setupMessageHandlers() : void
      {
         this.sysHandler = new SysHandler(this);
         this.extHandler = new ExtHandler(this);
         this.addMessageHandler("sys",this.sysHandler);
         this.addMessageHandler("xt",this.extHandler);
      }
      
      private function addMessageHandler(param1:String, param2:IMessageHandler) : void
      {
         if(this.messageHandlers[param1] == null)
         {
            this.messageHandlers[param1] = param2;
         }
         else
         {
            this.debugMessage("Warning, message handler called: " + param1 + " already exist!");
         }
      }
      
      private function debugMessage(param1:String) : void
      {
         var _loc2_:SFSEvent = null;
         if(this.debug)
         {
            _loc2_ = new SFSEvent(SFSEvent.onDebugMessage,{"message":param1});
            dispatchEvent(_loc2_);
         }
      }
      
      private function send(param1:Object, param2:String, param3:Number, param4:String) : void
      {
         var _loc5_:String = this.makeXmlHeader(param1);
         _loc5_ += "<body action=\'" + param2 + "\' r=\'" + param3 + "\'>" + param4 + "</body>" + this.closeHeader();
         this.debugMessage("[Sending]: encrypted SFS message, action=" + param2 + ", len=" + _loc5_.length);
         this.writeToSocket(_loc5_);
      }
      
      private function writeToSocket(param1:String) : void
      {
         var _loc2_:ByteArray;
         var _loc3_:String;
         if(this.ek2State != EK2_STATE_READY || this.ek2Session == null || !this.ek2Session.isReady || !this.physicalSocketConnected)
         {
            this.failEncryptedConnection("Application packet attempted before EK2 was ready");
            return;
         }
         _loc2_ = null;
         try
         {
            _loc2_ = new ByteArray();
            _loc2_.writeMultiByte(param1,"utf-8");
            if(_loc2_.length > EK2Config.MAX_PLAINTEXT_BYTES)
            {
               this.failEncryptedConnection("SFS packet exceeds EK2 plaintext limit");
               return;
            }
            _loc3_ = this.ek2Session.encryptRecord(_loc2_);
            this.writeRawEK2Record(_loc3_);
            this.restartInactivityTimer();
         }
         catch(param2:Error)
         {
            this.failEncryptedConnection("EK2 send failure: " + param2.message);
         }
         finally
         {
            EK2Crypto.wipe(_loc2_);
         }
      }
      
      private function makeXmlHeader(param1:Object) : String
      {
         var _loc3_:String = null;
         var _loc2_:String = "<msg";
         for(_loc3_ in param1)
         {
            _loc2_ += " " + _loc3_ + "=\'" + param1[_loc3_] + "\'";
         }
         return _loc2_ + ">";
      }
      
      private function closeHeader() : String
      {
         return "</msg>";
      }
      
      private function checkBuddyDuplicates(param1:String) : Boolean
      {
         var _loc3_:Object = null;
         var _loc2_:Boolean = false;
         for each(_loc3_ in this.buddyList)
         {
            if(_loc3_.name == param1)
            {
               _loc2_ = true;
               break;
            }
         }
         return _loc2_;
      }
      
      private function xmlReceived(param1:String) : void
      {
         var handlerId:String;
         var action:String;
         var roomId:int;
         var handler:IMessageHandler;
         var xmlData:XML = null;
         var msg:String = param1;
         try
         {
            var decodeStarted:int = getTimer();
            try { xmlData = new XML(msg); }
            finally { this.recordNativeTiming("socket_decode",getTimer()-decodeStarted); }
         }
         catch(e:*)
         {
            return;
         }
         handlerId = xmlData.@t;
         action = xmlData.body.@action;
         roomId = int(xmlData.body.@r);
         handler = this.messageHandlers[handlerId];
         if(handler != null)
         {
            var dispatchStarted:int = getTimer();
            try { handler.handleMessage(xmlData,XTMSG_TYPE_XML); }
            finally { this.recordNativeTiming("socket_dispatch",getTimer()-dispatchStarted); }
         }
      }
      
      private function jsonReceived(param1:String) : void
      {
         var decodeStarted:int = getTimer();
         var _loc2_:Object;
         try { _loc2_ = com.adobe.serialization.json.JSON.decode(param1); }
         finally { this.recordNativeTiming("socket_decode",getTimer()-decodeStarted); }
         var _loc3_:String = _loc2_["t"];
         var _loc4_:IMessageHandler = this.messageHandlers[_loc3_];
         if(_loc4_ != null)
         {
            if(_loc3_ == "xt" && this.inspectJsonExtensionResponse(_loc2_["b"]))
            {
               return;
            }
            var dispatchStarted:int = getTimer();
            try { _loc4_.handleMessage(_loc2_["b"],XTMSG_TYPE_JSON); }
            finally { this.recordNativeTiming("socket_dispatch",getTimer()-dispatchStarted); }
         }
      }
      
      private function strReceived(param1:String) : void
      {
         var decodeStarted:int = getTimer();
         var _loc2_:Array = param1.substr(1,param1.length - 2).split(MSG_STR);
         this.recordNativeTiming("socket_decode",getTimer()-decodeStarted);
         var _loc3_:String = _loc2_[0];
         var _loc4_:IMessageHandler = this.messageHandlers[_loc3_];
         if(_loc4_ != null)
         {
            var dispatchStarted:int = getTimer();
            try { _loc4_.handleMessage(_loc2_.splice(1,_loc2_.length - 1),XTMSG_TYPE_STR); }
            finally { this.recordNativeTiming("socket_dispatch",getTimer()-dispatchStarted); }
         }
      }
      
      private function getXmlRoomVariable(param1:Object) : String
      {
         var _loc2_:String = param1.name.toString();
         var _loc3_:* = param1.val;
         var _loc4_:String = param1.priv ? "1" : "0";
         var _loc5_:String = param1.persistent ? "1" : "0";
         var _loc6_:String = null;
         var _loc7_:* = typeof _loc3_;
         if(_loc7_ == "boolean")
         {
            _loc6_ = "b";
            _loc3_ = _loc3_ ? "1" : "0";
         }
         else if(_loc7_ == "number")
         {
            _loc6_ = "n";
         }
         else if(_loc7_ == "string")
         {
            _loc6_ = "s";
         }
         else if(_loc3_ == null && _loc7_ == "object" || _loc7_ == "undefined")
         {
            _loc6_ = "x";
            _loc3_ = "";
         }
         if(_loc6_ != null)
         {
            return "<var n=\'" + _loc2_ + "\' t=\'" + _loc6_ + "\' pr=\'" + _loc4_ + "\' pe=\'" + _loc5_ + "\'><![CDATA[" + _loc3_ + "]]></var>";
         }
         return "";
      }
      
      private function getXmlUserVariable(param1:Object) : String
      {
         var _loc3_:* = undefined;
         var _loc4_:String = null;
         var _loc5_:* = null;
         var _loc6_:String = null;
         var _loc2_:String = "<vars>";
         for(_loc6_ in param1)
         {
            _loc3_ = param1[_loc6_];
            _loc5_ = typeof _loc3_;
            _loc4_ = null;
            if(_loc5_ == "boolean")
            {
               _loc4_ = "b";
               _loc3_ = _loc3_ ? "1" : "0";
            }
            else if(_loc5_ == "number")
            {
               _loc4_ = "n";
            }
            else if(_loc5_ == "string")
            {
               _loc4_ = "s";
            }
            else if(_loc3_ == null && _loc5_ == "object" || _loc5_ == "undefined")
            {
               _loc4_ = "x";
               _loc3_ = "";
            }
            if(_loc4_ != null)
            {
               _loc2_ += "<var n=\'" + _loc6_ + "\' t=\'" + _loc4_ + "\'><![CDATA[" + _loc3_ + "]]></var>";
            }
         }
         return _loc2_ + "</vars>";
      }
      
      private function checkRoomList() : Boolean
      {
         var _loc1_:Boolean = true;
         if(this.roomList == null || this.roomList.length == 0)
         {
            _loc1_ = false;
            this.errorTrace("The room list is empty!\nThe client API cannot function properly until the room list is populated.\nPlease consult the documentation for more infos.");
         }
         return _loc1_;
      }
      
      private function checkJoin() : Boolean
      {
         var _loc1_:Boolean = true;
         if(this.activeRoomId < 0)
         {
            _loc1_ = false;
            this.errorTrace("You haven\'t joined any rooms!\nIn order to interact with the server you should join at least one room.\nPlease consult the documentation for more infos.");
         }
         return _loc1_;
      }
      
      private function errorTrace(param1:String) : void
      {
         this.debugMessage("[SFS] " + param1);
      }
      
      private function replaceSocketConnection() : void
      {
         this.retireSocketConnection(this.socketConnection);
         this.socketConnection = new Socket();
         this.socketConnection.addEventListener(Event.CONNECT,this.handleSocketConnection);
         this.socketConnection.addEventListener(Event.CLOSE,this.handleSocketDisconnection);
         this.socketConnection.addEventListener(ProgressEvent.SOCKET_DATA,this.handleSocketData);
         this.socketConnection.addEventListener(IOErrorEvent.IO_ERROR,this.handleIOError);
         this.socketConnection.addEventListener(IOErrorEvent.NETWORK_ERROR,this.handleIOError);
         this.socketConnection.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.handleSecurityError);
         this.physicalSocketConnected = false;
      }
      
      private function retireSocketConnection(param1:Socket) : void
      {
         if(param1 == null)
         {
            return;
         }
         if(param1 === this.pendingReceiveSocket)
         {
            this.receiveTimer.reset();
            this.pendingReceiveSocket = null;
         }
         param1.removeEventListener(Event.CONNECT,this.handleSocketConnection);
         param1.removeEventListener(Event.CLOSE,this.handleSocketDisconnection);
         param1.removeEventListener(ProgressEvent.SOCKET_DATA,this.handleSocketData);
         param1.removeEventListener(IOErrorEvent.IO_ERROR,this.handleIOError);
         param1.removeEventListener(IOErrorEvent.NETWORK_ERROR,this.handleIOError);
         param1.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.handleSecurityError);
         if(param1 === this.socketConnection)
         {
            this.socketConnection = null;
         }
         try
         {
            param1.close();
         }
         catch(param2:Error)
         {
            this.debugMessage("[EK2] retired a socket without an open connection");
         }
         this.physicalSocketConnected = false;
      }
      
      private function beginEncryptedEndpointAttempt(param1:String, param2:int) : void
      {
         this.pendingHost = param1;
         this.pendingPort = param2;
         this.ek2State = EK2_STATE_HANDSHAKING;
         this.ek2HandshakePhase = "ENTROPY";
         this.startHandshakeTimer(EK2Config.ENTROPY_TIMEOUT_MS);
         this.requestSecureEntropy();
      }
      
      private function canTryEncryptedFallback() : Boolean
      {
         if(this.connected || this.ek2State != EK2_STATE_HANDSHAKING || this.ek2FallbackAttempted)
         {
            return false;
         }
         if(this.ek2FallbackHost == null || this.ek2FallbackHost.length == 0 || this.ek2FallbackPort < 1)
         {
            return false;
         }
         if(this.ek2FallbackHost == this.pendingHost && this.ek2FallbackPort == this.pendingPort)
         {
            return false;
         }
         return this.ek2HandshakePhase == "CONNECTING" || this.ek2HandshakePhase == "WAIT_SH";
      }
      
      private function tryEncryptedFallback(param1:String) : Boolean
      {
         if(!this.canTryEncryptedFallback())
         {
            return false;
         }
         this.debugMessage("[EK2] primary endpoint failed before authentication (" + param1 + "); trying encrypted fallback " + this.ek2FallbackHost + ":" + this.ek2FallbackPort);
         this.ek2FallbackAttempted = true;
         this.retireSocketConnection(this.socketConnection);
         this.handshakeTimer.stop();
         this.partialRecordTimer.stop();
         this.inactivityTimer.stop();
         this.cancelEntropyRequest();
         this.byteBuffer = new ByteArray();
         if(this.ek2Session != null)
         {
            this.ek2Session.dispose();
            this.ek2Session = null;
         }
         this.ek2ClientHello = null;
         this.physicalSocketConnected = false;
         this.beginEncryptedEndpointAttempt(this.ek2FallbackHost,this.ek2FallbackPort);
         return true;
      }
      
      private function requestSecureEntropy() : void
      {
         var _loc1_:Object;
         var _loc2_:Object;
         this.cancelEntropyRequest();
         _loc1_ = null;
         _loc2_ = null;
         if(ExternalInterface.available)
         {
            try
            {
               _loc2_ = ExternalInterface.call(EK2Config.BROWSER_ENTROPY_PROBE_FUNCTION);
            }
            catch(param1:Error)
            {
               this.debugMessage("[EK2] browser entropy bridge is unavailable");
            }
         }
         if(_loc2_ === true)
         {
            try
            {
               _loc1_ = ExternalInterface.call(EK2Config.BROWSER_ENTROPY_FUNCTION,64);
            }
            catch(param2:Error)
            {
               this.failEncryptedConnection("Secure browser WebCrypto entropy is unavailable");
               return;
            }
            if(_loc1_ == null || String(_loc1_).length == 0 || String(_loc1_) == "undefined")
            {
               this.failEncryptedConnection("Secure browser WebCrypto returned no entropy");
               return;
            }
            this.acceptSecureEntropy(String(_loc1_),"Browser WebCrypto");
            return;
         }
         this.requestLauncherEntropy();
      }
      
      private function requestLauncherEntropy() : void
      {
         this.cancelEntropyRequest();
         Security.loadPolicyFile(EK2Config.ENTROPY_POLICY_URL);
         this.entropyLoader = new URLLoader();
         this.entropyLoader.addEventListener(Event.COMPLETE,this.handleEntropyLoaded);
         this.entropyLoader.addEventListener(IOErrorEvent.IO_ERROR,this.handleEntropyError);
         this.entropyLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.handleEntropyError);
         try
         {
            this.entropyLoader.load(new URLRequest(EK2Config.ENTROPY_URL));
         }
         catch(param1:Error)
         {
            this.debugMessage("[EK2] entropy request was already closed");
            this.failEncryptedConnection("Secure launcher entropy is unavailable: " + param1.message);
         }
      }
      
      private function handleEntropyLoaded(param1:Event) : void
      {
         var _loc2_:URLLoader = param1.currentTarget as URLLoader;
         if(_loc2_ == null || _loc2_ !== this.entropyLoader)
         {
            this.disposeEntropyLoader(_loc2_);
            return;
         }
         if(this.ek2State != EK2_STATE_HANDSHAKING)
         {
            this.cancelEntropyRequest();
            return;
         }
         var _loc3_:String = String(_loc2_.data);
         this.cancelEntropyRequest();
         this.acceptSecureEntropy(_loc3_,"Secure launcher");
      }
      
      private function acceptSecureEntropy(param1:String, param2:String) : void
      {
         var _loc3_:ByteArray;
         if(this.ek2State != EK2_STATE_HANDSHAKING)
         {
            return;
         }
         _loc3_ = null;
         try
         {
            _loc3_ = EK2Crypto.base64UrlDecodeStrict(param1);
            if(_loc3_.length != 64)
            {
               this.failEncryptedConnection(param2 + " returned the wrong entropy length");
               return;
            }
            this.ek2Session = new EK2Session(_loc3_,EK2Config.ACTIVE_KEY_ID,this.initialLoginAttemptId);
            this.initialLoginAttemptId = null;
            if(!isCanonicalUuidV4(this.loginFlowIdValue))
            {
               this.loginFlowIdValue = this.ek2Session.loginAttemptId;
            }
            this.ek2Session.setLoginFlowId(this.loginFlowIdValue);
            this.currentLoginAttemptIdValue = this.ek2Session.loginAttemptId;
            this.ek2ClientHello = this.ek2Session.createClientHello();
         }
         catch(param3:Error)
         {
            this.failEncryptedConnection(param2 + " entropy was rejected: " + param3.message);
         }
         finally
         {
            EK2Crypto.wipe(_loc3_);
         }
         if(this.ek2State != EK2_STATE_HANDSHAKING)
         {
            return;
         }
         try
         {
            this.replaceSocketConnection();
            this.ek2HandshakePhase = "CONNECTING";
            this.startHandshakeTimer(EK2Config.CONNECT_TIMEOUT_MS);
            Security.loadPolicyFile("xmlsocket://" + this.pendingHost + ":" + this.pendingPort);
            this.socketConnection.connect(this.pendingHost,this.pendingPort);
         }
         catch(param4:Error)
         {
            if(!this.tryEncryptedFallback("socket setup failed"))
            {
               this.failEncryptedConnection("EK2 socket setup failed: " + param4.message);
            }
         }
      }
      
      private function handleEntropyError(param1:ErrorEvent) : void
      {
         var _loc2_:URLLoader = param1.currentTarget as URLLoader;
         if(_loc2_ == null || _loc2_ !== this.entropyLoader)
         {
            this.disposeEntropyLoader(_loc2_);
            return;
         }
         this.cancelEntropyRequest();
         this.failEncryptedConnection("Secure launcher entropy request failed");
      }
      
      private function cancelEntropyRequest() : void
      {
         this.disposeEntropyLoader(this.entropyLoader);
      }
      
      private function disposeEntropyLoader(param1:URLLoader) : void
      {
         if(param1 == null)
         {
            return;
         }
         param1.removeEventListener(Event.COMPLETE,this.handleEntropyLoaded);
         param1.removeEventListener(IOErrorEvent.IO_ERROR,this.handleEntropyError);
         param1.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.handleEntropyError);
         if(param1 === this.entropyLoader)
         {
            this.entropyLoader = null;
         }
         try
         {
            param1.close();
         }
         catch(param2:Error)
         {
            this.debugMessage("[EK2] retired an entropy request that was already closed");
         }
      }
      
      private function startHandshakeTimer(param1:uint) : void
      {
         this.handshakeTimer.reset();
         this.handshakeTimer.delay = param1;
         this.handshakeTimer.start();
      }
      
      private function handleHandshakeTimeout(param1:TimerEvent) : void
      {
         var _loc2_:String = this.ek2HandshakePhase;
         if(!this.tryEncryptedFallback("timeout during " + _loc2_))
         {
            this.failEncryptedConnection("EK2 connection timed out during " + _loc2_);
         }
      }
      
      private function restartPartialRecordTimer() : void
      {
         this.partialRecordTimer.reset();
         this.partialRecordTimer.start();
      }
      
      private function handlePartialRecordTimeout(param1:TimerEvent) : void
      {
         this.failEncryptedConnection("EK2 partial record timed out");
      }
      
      private function restartInactivityTimer() : void
      {
         if(this.ek2State != EK2_STATE_READY)
         {
            return;
         }
         this.inactivityTimer.reset();
         this.inactivityTimer.start();
      }
      
      private function handleInactivityTimeout(param1:TimerEvent) : void
      {
         this.failEncryptedConnection("EK2 connection was inactive for too long");
      }
      
      private function writeRawEK2Record(param1:String) : void
      {
         if(param1 == null || param1.length == 0 || param1.indexOf(String.fromCharCode(0)) >= 0 || param1.length > EK2Config.MAX_ENCODED_RECORD_BYTES)
         {
            throw new Error("Invalid outbound EK2 record");
         }
         if(this.socketConnection == null || !this.socketConnection.connected)
         {
            throw new Error("EK2 socket is not connected");
         }
         var _loc2_:ByteArray = new ByteArray();
         _loc2_.writeMultiByte(param1,"utf-8");
         _loc2_.writeByte(0);
         this.socketConnection.writeBytes(_loc2_);
         this.socketConnection.flush();
         EK2Crypto.wipe(_loc2_);
      }
      
      private function handleHttpConnect(param1:HttpEvent) : void
      {
         this.failEncryptedConnection("BlueBox transport is disabled by EK2");
      }
      
      private function handleHttpClose(param1:HttpEvent) : void
      {
         this.failEncryptedConnection("BlueBox transport closed");
      }
      
      private function handleHttpData(param1:HttpEvent) : void
      {
         this.failEncryptedConnection("BlueBox data is forbidden by EK2");
      }
      
      private function handleDelayedPoll() : void
      {
         this.failEncryptedConnection("BlueBox polling is disabled by EK2");
      }
      
      private function handleHttpError(param1:HttpEvent) : void
      {
         this.failEncryptedConnection("BlueBox transport error");
      }
      
      private function handleSocketConnection(param1:Event) : void
      {
         if(param1.currentTarget !== this.socketConnection)
         {
            return;
         }
         this.physicalSocketConnected = true;
         if(this.ek2State != EK2_STATE_HANDSHAKING || this.ek2Session == null || this.ek2ClientHello == null || this.ek2HandshakePhase != "CONNECTING")
         {
            this.failEncryptedConnection("Unexpected socket connection outside EK2 handshake");
            return;
         }
         try
         {
            this.ek2HandshakePhase = "WAIT_SH";
            this.startHandshakeTimer(EK2Config.SERVER_HELLO_TIMEOUT_MS);
            this.writeRawEK2Record(this.ek2ClientHello);
         }
         catch(param2:Error)
         {
            if(!this.tryEncryptedFallback("client hello write failed"))
            {
               this.failEncryptedConnection("EK2 client hello failed: " + param2.message);
            }
         }
      }
      
      private function handleSocketDisconnection(param1:Event) : void
      {
         if(param1.currentTarget !== this.socketConnection)
         {
            return;
         }
         var _loc2_:Boolean = this.connected;
         this.physicalSocketConnected = false;
         if(!_loc2_ && this.tryEncryptedFallback("socket closed before authentication"))
         {
            return;
         }
         this.initialize();
         if(_loc2_)
         {
            dispatchEvent(new SFSEvent(SFSEvent.onConnectionLost,{"error":"Encrypted socket closed"}));
         }
         else
         {
            this.dispatchConnectionError("Encrypted socket closed before login");
         }
      }
      
      private function handleIOError(param1:IOErrorEvent) : void
      {
         if(param1.currentTarget !== this.socketConnection)
         {
            return;
         }
         if(!this.tryEncryptedFallback("socket I/O failure"))
         {
            this.failEncryptedConnection("Encrypted socket I/O failure");
         }
      }
      
      private function tryBlueBoxConnection(param1:ErrorEvent) : void
      {
         this.failEncryptedConnection("Socket connection failed; BlueBox is disabled");
      }
      
      private function handleSocketError(param1:SecurityErrorEvent) : void
      {
         this.failEncryptedConnection("Encrypted socket security failure");
      }
      
      private function handleSecurityError(param1:SecurityErrorEvent) : void
      {
         if(param1.currentTarget !== this.socketConnection)
         {
            return;
         }
         if(!this.tryEncryptedFallback("socket policy/security failure"))
         {
            this.failEncryptedConnection("Encrypted socket security failure");
         }
      }
      
      private function handleSocketData(param1:Event) : void
      {
         var source:Socket = param1.currentTarget as Socket;
         if(source == null || source !== this.socketConnection || this.pendingReceiveSocket === source)
         {
            return;
         }
         this.drainSocketData(source);
      }

      private function resumeSocketData(event:TimerEvent) : void
      {
         var source:Socket = this.pendingReceiveSocket;
         this.pendingReceiveSocket = null;
         if(source != null && source === this.socketConnection && source.connected)
         {
            this.drainSocketData(source);
         }
      }

      private function drainSocketData(source:Socket) : void
      {
         var started:int = getTimer();
         var bytes:int = 0;
         var records:int = 0;
         // Game callbacks may replace the connection. Never touch its successor.
         while(source === this.socketConnection && source.connected && source.bytesAvailable > 0)
         {
            var value:int = int(source.readUnsignedByte());
            bytes++;
            if(value != 0)
            {
               this.byteBuffer.writeByte(value);
               if(this.byteBuffer.length > EK2Config.MAX_ENCODED_RECORD_BYTES)
               {
                  this.failEncryptedConnection("EK2 record exceeds encoded limit");
                  return;
               }
            }
            else
            {
               this.partialRecordTimer.stop();
               if(this.byteBuffer.length == 0)
               {
                  this.failEncryptedConnection("Empty EK2 record received");
                  return;
               }
               this.byteBuffer.position = 0;
               var record:String = this.byteBuffer.readUTFBytes(this.byteBuffer.length);
               this.byteBuffer = new ByteArray();
               if(!this.processEK2Record(record))
               {
                  return;
               }
               records++;
            }
            // Check after callbacks and every 256 bytes instead of calling the clock
            // (or resetting a Timer) for every byte of a large encrypted record.
            if(records >= RECEIVE_RECORD_LIMIT || bytes >= RECEIVE_BYTE_LIMIT ||
               ((value == 0 || (bytes & 255) == 0) && getTimer() - started >= RECEIVE_BUDGET_MS))
            {
               break;
            }
         }
         if(source !== this.socketConnection || !source.connected)
         {
            return;
         }
         if(bytes > 0 && this.byteBuffer.length > 0)
         {
            this.restartPartialRecordTimer();
         }
         if(source.bytesAvailable > 0)
         {
            this.pendingReceiveSocket = source;
            this.receiveTimer.reset();
            this.receiveTimer.start();
         }
      }

      private function processEK2Record(param1:String) : Boolean
      {
         var _loc2_:String;
         var _loc3_:Object;
         var _loc4_:String;
         var _loc5_:ByteArray;
         var _loc6_:String;
         try
         {
            if(this.ek2State == EK2_STATE_HANDSHAKING)
            {
               if(this.ek2HandshakePhase == "WAIT_SH")
               {
                  if(param1.indexOf("EK2|SH|") != 0)
                  {
                     throw new Error("Expected EK2 server hello");
                  }
                  _loc2_ = this.ek2Session.acceptServerHello(param1,this.ek2ClientHello);
                  this.ek2HandshakePhase = "WAIT_OK";
                  this.startHandshakeTimer(EK2Config.SERVER_ACK_TIMEOUT_MS);
                  this.writeRawEK2Record(_loc2_);
                  return true;
               }
               if(this.ek2HandshakePhase == "WAIT_OK")
               {
                  if(param1.indexOf("EK2|OK|") != 0)
                  {
                     throw new Error("Expected EK2 server ACK");
                  }
                  this.ek2Session.acceptServerAck(param1);
                  this.ek2State = EK2_STATE_READY;
                  this.ek2HandshakePhase = "COMPLETE";
                  this.handshakeTimer.stop();
                  _loc3_ = {"t":"sys"};
                  _loc4_ = "<ver v=\'" + this.majVersion.toString() + this.minVersion.toString() + this.subVersion.toString() + "\' />";
                  this.send(_loc3_,"verChk",0,_loc4_);
                  return true;
               }
               throw new Error("Unexpected EK2 handshake record");
            }
            if(this.ek2State != EK2_STATE_READY || this.ek2Session == null)
            {
               throw new Error("EK2 data arrived outside READY state");
            }
            // EK2 framing is ASCII; length here is wire bytes excluding the NUL delimiter.
            var recordStarted:int = getTimer();
            this.recordNativeTiming("socket_wire",0,param1.length);
            var decryptStarted:int = getTimer();
            try { _loc5_ = this.ek2Session.decryptRecord(param1); }
            finally { this.recordNativeTiming("socket_decrypt",getTimer()-decryptStarted); }
            try
            {
               this.restartInactivityTimer();
               _loc5_.position = 0;
               this.recordNativeTiming("socket_plain",0,_loc5_.length);
               var utf8Started:int = getTimer();
               try { _loc6_ = _loc5_.readUTFBytes(_loc5_.length); }
               finally { this.recordNativeTiming("socket_utf8",getTimer()-utf8Started); }
               this.handleMessage(_loc6_);
               return true;
            }
            finally
            {
               EK2Crypto.wipe(_loc5_);
               this.recordNativeTiming("socket_record",getTimer()-recordStarted,param1.length);
            }
         }
         catch(param2:Error)
         {
            this.failEncryptedConnection("EK2 receive failure: " + param2.message);
            return false;
         }
         return undefined;
      }
      
      // Fixed names and numeric aggregates only. Never pass packet bodies or account data.
      // A missing diagnostic bridge must not change transport or gameplay behavior.
      private function recordNativeTiming(stage:String,elapsed:int,bytes:int=0) : void
      {
         try
         {
            ExternalInterface.call("ekolokoNativePerformance",{stage:stage,count:1,
               totalMs:Math.max(0,elapsed),maxMs:Math.max(0,elapsed),bytes:bytes,
               maxBytes:bytes,slowCount:elapsed>=50?1:0});
         }
         catch(ignored:Error) {}
      }

      private function failEncryptedConnection(param1:String) : void
      {
         if(this.ek2State == EK2_STATE_FAILED)
         {
            return;
         }
         var _loc2_:Boolean = this.connected;
         var _loc3_:String = this.ek2HandshakePhase;
         this.ek2State = EK2_STATE_FAILED;
         this.handshakeTimer.stop();
         this.partialRecordTimer.stop();
         this.inactivityTimer.stop();
         this.cancelEntropyRequest();
         this.byteBuffer = new ByteArray();
         if(this.ek2Session != null)
         {
            this.ek2Session.dispose();
            this.ek2Session = null;
         }
         this.ek2ClientHello = null;
         this.ek2HandshakePhase = "FAILED";
         this.physicalSocketConnected = false;
         this.retireSocketConnection(this.socketConnection);
         this.connected = false;
         this.isHttpMode = false;
         this.debugMessage("[EK2] " + param1);
         if(_loc2_)
         {
            dispatchEvent(new SFSEvent(SFSEvent.onConnectionLost,{
               "error":param1,
               "encryption":true
            }));
         }
         else
         {
            this.dispatchConnectionError(param1,_loc3_);
         }
      }
      
      private function resetPhysicalCryptoState() : void
      {
         this.resetLoginResponseTracking();
         this.retireSocketConnection(this.socketConnection);
         this.cancelEntropyRequest();
         if(this.handshakeTimer != null)
         {
            this.handshakeTimer.stop();
         }
         if(this.partialRecordTimer != null)
         {
            this.partialRecordTimer.stop();
         }
         if(this.inactivityTimer != null)
         {
            this.inactivityTimer.stop();
         }
         if(this.ek2Session != null)
         {
            this.ek2Session.dispose();
            this.ek2Session = null;
         }
         this.byteBuffer = new ByteArray();
         this.ek2ClientHello = null;
         this.ek2HandshakePhase = "CLOSED";
         this.pendingHost = null;
         this.pendingPort = 0;
         this.physicalSocketConnected = false;
         this.ek2State = EK2_STATE_DISCONNECTED;
      }
      
      override public function dispatchEvent(event:Event):Boolean
      {
         ExternalInterface.call("ekolokoNativeSocketDispatch","begin",event.type);
         try { return super.dispatchEvent(event); }
         finally { ExternalInterface.call("ekolokoNativeSocketDispatch","end",event.type); }
      }

      public function set ignoreMsgs(param1:Boolean) : *
      {
         this.ignore = param1;
      }
      
      private function isIgnoredBubbleCannonAck(param1:String) : Boolean
      {
         var _loc2_:Object = null;
         var _loc3_:Object = null;
         var _loc4_:Object = null;
         var _loc5_:String = null;
         var _loc6_:int = 0;
         if(param1 == null || param1.length == 0 || param1.charAt(0) != MSG_JSON)
         {
            return false;
         }
         try
         {
            _loc2_ = com.adobe.serialization.json.JSON.decode(param1);
         }
         catch(_loc7_:*)
         {
            return false;
         }
         if(_loc2_ == null || typeof _loc2_ != "object" || _loc2_ is Array || _loc2_["t"] !== "xt" || _loc2_["b"] == null || typeof _loc2_["b"] != "object" || _loc2_["b"] is Array)
         {
            return false;
         }
         for(_loc5_ in _loc2_)
         {
            if(_loc5_ != "t" && _loc5_ != "b")
            {
               return false;
            }
            _loc6_++;
         }
         if(_loc6_ != 2)
         {
            return false;
         }
         _loc3_ = _loc2_["b"];
         _loc6_ = 0;
         for(_loc5_ in _loc3_)
         {
            if(_loc5_ != "o" && _loc5_ != "r")
            {
               return false;
            }
            _loc6_++;
         }
         if(_loc6_ != 2 || _loc3_["r"] !== -1 || _loc3_["o"] == null || typeof _loc3_["o"] != "object" || _loc3_["o"] is Array)
         {
            return false;
         }
         _loc4_ = _loc3_["o"];
         _loc6_ = 0;
         for(_loc5_ in _loc4_)
         {
            if(_loc5_ != "21" && _loc5_ != "92" && _loc5_ != "93" && _loc5_ != "685" && _loc5_ != "686" && _loc5_ != "88")
            {
               return false;
            }
            _loc6_++;
         }
         if(_loc4_["93"] !== 1 || typeof _loc4_["92"] != "string")
         {
            return false;
         }
         if(_loc6_ == 5)
         {
            return _loc4_["21"] === "680" && typeof _loc4_["685"] == "number" && Boolean(isFinite(Number(_loc4_["685"]))) && Math.floor(Number(_loc4_["685"])) == Number(_loc4_["685"]) && Number(_loc4_["685"]) >= 0 && Number(_loc4_["685"]) <= 2147483648 && typeof _loc4_["686"] == "number" && (Number(_loc4_["686"]) == 0 || Number(_loc4_["686"]) == 1);
         }
         if(_loc6_ == 6)
         {
            return _loc4_["21"] === "680" && typeof _loc4_["685"] == "number" && Boolean(isFinite(Number(_loc4_["685"]))) && Math.floor(Number(_loc4_["685"])) == Number(_loc4_["685"]) && Number(_loc4_["685"]) >= 0 && Number(_loc4_["685"]) <= 2147483648 && typeof _loc4_["686"] == "number" && (Number(_loc4_["686"]) == 0 || Number(_loc4_["686"]) == 1 || Number(_loc4_["686"]) == 2) && typeof _loc4_["88"] == "number" && Boolean(isFinite(Number(_loc4_["88"]))) && Math.floor(Number(_loc4_["88"])) == Number(_loc4_["88"]) && Number(_loc4_["88"]) >= 0 && Number(_loc4_["88"]) <= 9007199254740991;
         }
         return _loc6_ == 4 && _loc4_["21"] === "702" && typeof _loc4_["88"] == "number" && Boolean(isFinite(Number(_loc4_["88"]))) && Math.floor(Number(_loc4_["88"])) == Number(_loc4_["88"]) && Number(_loc4_["88"]) >= 0 && Number(_loc4_["88"]) <= 9007199254740991;
      }
      
      private function hasExactProofOfPlayKeys(param1:Object, param2:Array) : Boolean
      {
         var _loc3_:String = null;
         var _loc4_:int = 0;
         if(param1 == null || param2 == null)
         {
            return false;
         }
         for(_loc3_ in param1)
         {
            if(param2.indexOf(_loc3_) < 0)
            {
               return false;
            }
            _loc4_++;
         }
         return _loc4_ == param2.length;
      }
      
      private function isProofOfPlayInteger(param1:*, param2:Number, param3:Number) : Boolean
      {
         return typeof param1 == "number" && Boolean(isFinite(Number(param1))) && Math.floor(Number(param1)) == Number(param1) && Number(param1) >= param2 && Number(param1) <= param3;
      }
      
      private function isIgnoredProofOfPlayResponse(param1:String) : Boolean
      {
         var _loc2_:Object = null;
         var _loc3_:Object = null;
         var _loc4_:Object = null;
         var _loc5_:String = null;
         var _loc6_:String = null;
         var _loc7_:int = 0;
         if(param1 == null || param1.length == 0 || param1.charAt(0) != MSG_JSON)
         {
            return false;
         }
         try
         {
            _loc2_ = com.adobe.serialization.json.JSON.decode(param1);
         }
         catch(_loc8_:*)
         {
            return false;
         }
         if(_loc2_ == null || typeof _loc2_ != "object" || _loc2_ is Array || _loc2_["t"] !== "xt" || _loc2_["b"] == null || typeof _loc2_["b"] != "object" || _loc2_["b"] is Array)
         {
            return false;
         }
         for(_loc5_ in _loc2_)
         {
            if(_loc5_ != "t" && _loc5_ != "b")
            {
               return false;
            }
            _loc7_++;
         }
         if(_loc7_ != 2)
         {
            return false;
         }
         _loc3_ = _loc2_["b"];
         _loc7_ = 0;
         for(_loc5_ in _loc3_)
         {
            if(_loc5_ != "o" && _loc5_ != "r")
            {
               return false;
            }
            _loc7_++;
         }
         if(_loc7_ != 2 || _loc3_["r"] !== -1 || _loc3_["o"] == null || typeof _loc3_["o"] != "object" || _loc3_["o"] is Array)
         {
            return false;
         }
         _loc4_ = _loc3_["o"];
         _loc6_ = _loc4_["21"] == null ? "" : String(_loc4_["21"]);
         if(_loc6_ == "168")
         {
            return this.hasExactProofOfPlayKeys(_loc4_,["21","92","93","718"]) && _loc4_["21"] === "168" && this.isProofOfPlayInteger(_loc4_["93"],1,999999999) && typeof _loc4_["92"] == "string" && String(_loc4_["92"]).length >= 1 && String(_loc4_["92"]).length <= 64 && (_loc4_["718"] === "required" || _loc4_["718"] === "ready");
         }
         if(_loc6_ == "166")
         {
            return this.hasExactProofOfPlayKeys(_loc4_,["21","22","92","93","718","719"]) && _loc4_["21"] === "166" && _loc4_["22"] === "Verification is required before the game can start" && this.isProofOfPlayInteger(_loc4_["93"],1,999999999) && typeof _loc4_["92"] == "string" && String(_loc4_["92"]).length >= 1 && String(_loc4_["92"]).length <= 64 && _loc4_["718"] === "required" && _loc4_["719"] === "proof_required_before_start";
         }
         if(_loc6_ == "706")
         {
            if(!this.hasExactProofOfPlayKeys(_loc4_,["21","709","710","712","713","716","717","718","720","722"]) || _loc4_["21"] !== "706" || typeof _loc4_["709"] != "string" || !/^[0-9a-f]{64}$/.test(String(_loc4_["709"])) || !this.isProofOfPlayInteger(_loc4_["710"],2,2) || _loc4_["712"] !== "drag" && _loc4_["712"] !== "tap" || !this.isProofOfPlayInteger(_loc4_["713"],1,1) || !this.isProofOfPlayInteger(_loc4_["716"],680,680) || !this.isProofOfPlayInteger(_loc4_["717"],230,230) || _loc4_["718"] !== "active" || !this.isProofOfPlayInteger(_loc4_["720"],1,60000) || typeof _loc4_["722"] != "string")
            {
               return false;
            }
            return _loc4_["722"] === "/ekoloko-web/proofOfPlayImage.php?c=" + _loc4_["709"];
         }
         if(_loc6_ == "707")
         {
            if(!this.hasExactProofOfPlayKeys(_loc4_,["21","709","710","713","718","719","720","721"]) || _loc4_["21"] !== "707" || typeof _loc4_["709"] != "string" || !/^[0-9a-f]{64}$/.test(String(_loc4_["709"])) || !this.isProofOfPlayInteger(_loc4_["710"],2,2) || !this.isProofOfPlayInteger(_loc4_["713"],1,2) || !this.isProofOfPlayInteger(_loc4_["720"],0,60000) || !this.isProofOfPlayInteger(_loc4_["721"],0,60000))
            {
               return false;
            }
            if(_loc4_["718"] !== "active" && _loc4_["718"] !== "passed" && _loc4_["718"] !== "failed" && _loc4_["718"] !== "expired")
            {
               return false;
            }
            return _loc4_["719"] === "passed" || _loc4_["719"] === "new_challenge" || _loc4_["719"] === "attempts_exhausted" || _loc4_["719"] === "kill_switch_release" || _loc4_["719"] === "accepted";
         }
         if(_loc6_ == "708")
         {
            if(this.hasExactProofOfPlayKeys(_loc4_,["21","93","710","718","719","721"]))
            {
               return _loc4_["21"] === "708" && this.isProofOfPlayInteger(_loc4_["93"],1,999999999) && this.isProofOfPlayInteger(_loc4_["710"],2,2) && _loc4_["718"] === "required" && _loc4_["719"] === "challenge_required" && this.isProofOfPlayInteger(_loc4_["721"],0,0);
            }
            return this.hasExactProofOfPlayKeys(_loc4_,["21","710","718","719","721"]) && _loc4_["21"] === "708" && this.isProofOfPlayInteger(_loc4_["710"],2,2) && _loc4_["718"] === "error" && typeof _loc4_["719"] == "string" && String(_loc4_["719"]).length >= 1 && String(_loc4_["719"]).length <= 64 && this.isProofOfPlayInteger(_loc4_["721"],0,60000);
         }
         return false;
      }
      
      private function handleMessage(param1:String) : void
      {
         if(this.ignore && !this.isIgnoredBubbleCannonAck(param1) && !this.isIgnoredProofOfPlayResponse(param1))
         {
            return;
         }
         if(param1 != "ok")
         {
            this.debugMessage("[ RECEIVED ]: authenticated encrypted SFS message, len=" + param1.length);
         }
         var _loc2_:String = param1.charAt(0);
         if(_loc2_ == MSG_XML)
         {
            this.xmlReceived(param1);
         }
         else if(_loc2_ == MSG_STR)
         {
            this.strReceived(param1);
         }
         else if(_loc2_ == MSG_JSON)
         {
            this.jsonReceived(param1);
         }
      }
      
      private function dispatchConnectionError(param1:String = "I/O Error", param2:String = null) : void
      {
         var _loc3_:Object = {};
         _loc3_.success = false;
         _loc3_.error = param1;
         _loc3_.encryption = true;
         _loc3_.ek2Phase = param2 == null ? this.ek2HandshakePhase : param2;
         var _loc4_:SFSEvent = new SFSEvent(SFSEvent.onConnection,_loc3_);
         dispatchEvent(_loc4_);
      }
   }
}

