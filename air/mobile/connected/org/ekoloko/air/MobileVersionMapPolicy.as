package org.ekoloko.air {
    import flash.utils.ByteArray;
    import air.security.Digest;

    /** Only a text-catalog counter may advance independently of the signed SWFs. */
    public final class MobileVersionMapPolicy {
        public static function compatible(current:ByteArray, manifest:Object, baseline:String, mainSha:String):Boolean {
            if (!current || current.length > 1048576 || !manifest) return false;
            var bytes:ByteArray = new ByteArray();
            try {
                bytes.writeUTFBytes(baseline);
                if (!baseline || bytes.length > 1048576 || hash(bytes) != manifest.versionConfigSha256 ||
                    !manifest.assets || !manifest.assets["main.swf"] || manifest.assets["main.swf"].sha256 != mainSha) return false;
                var position:uint = current.position;
                current.position = 0;
                var live:String = current.readUTFBytes(current.length);
                current.position = position;
                var old:Object = parse(baseline), next:Object = parse(live);
                return next.counter >= old.counter && next.tree == old.tree;
            } catch (error:Error) { return false; }
        }
        private static function hash(bytes:ByteArray):String {
            bytes.position=0;
            var digest:ByteArray=Digest.hash(Digest.SHA256,bytes), value:String="";
            for(var i:uint=0;i<digest.length;i++) value+=("0"+digest[i].toString(16)).substr(-2);
            return value;
        }
        private static function parse(source:String):Object {
            if (/<!DOCTYPE|<!ENTITY/i.test(source)) throw new Error("xml_declaration");
            var root:XML = new XML(source);
            if (String(root.localName()) != "data") throw new Error("map_root");
            var fields:XMLList = root.elements("text");
            if (fields.length() != 1 || fields[0].attributes().length() || fields[0].elements().length()) throw new Error("text_schema");
            var value:String = trim(String(fields[0]));
            if (!/^[0-9]{1,15}$/.test(value)) throw new Error("text_counter");
            var counter:Number = Number(value);
            fields[0].setChildren("0");
            return {counter:counter,tree:JSON.stringify(canonical(root,0,{left:10000}))};
        }
        private static function canonical(node:XML, depth:uint, budget:Object):Object {
            if (depth > 32 || --budget.left < 0) throw new Error("map_depth");
            if (node.nodeKind() == "text") return trim(String(node));
            if (node.nodeKind() == "comment" || node.nodeKind() == "processing-instruction") return null;
            if (node.nodeKind() != "element" || String(node.namespace().uri) != "" || node.namespaceDeclarations().length) throw new Error("map_namespace");
            var attrs:Array = [], children:Array = [];
            for each (var attr:XML in node.attributes()) {
                if (String(attr.namespace().uri) != "") throw new Error("attribute_namespace");
                attrs.push(JSON.stringify([String(attr.localName()),String(attr)]));
            }
            attrs.sort();
            for each (var child:XML in node.children()) {
                var part:Object = canonical(child,depth+1,budget);
                if (part !== null && part !== "") children.push(part);
            }
            return [String(node.localName()),attrs,children];
        }
        private static function trim(value:String):String { return value.replace(/^\s+|\s+$/g,""); }
    }
}
