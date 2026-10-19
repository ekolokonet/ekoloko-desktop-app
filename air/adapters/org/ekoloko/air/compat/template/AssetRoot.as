package org.ekoloko.air.compat.template {
    import flash.display.MovieClip;
    import flash.system.ApplicationDomain;

    // AIR does not associate a document class's constructor with its root
    // timeline. ItemMC/NpcMC are bound to library sprites at build time.
    // Preserve the game's existing content.constructor cloning contract.
    public dynamic class AssetRoot extends MovieClip {
        private var contentClip:MovieClip;
        public function AssetRoot() {
            super();
            var type:Class = ApplicationDomain.currentDomain.getDefinition("__EKOLOKO_DOCUMENT_CLASS__") as Class;
            this["constructor"] = type;
            contentClip = new type();
            addChild(contentClip);
        }
        // Recycle objects, NPCs and emoticons use getMC() instead of the
        // constructor property. Both must return the original library class.
        public function getMC():Class { return this["constructor"] as Class; }
        // NPCDisplayData reads these from the loaded document before cloning.
        public function get blockingMC():* { return Object(contentClip).blockingMC; }
        public function get bubbleLocation():* { return Object(contentClip).bubbleLocation; }
        public function get helper():* { return Object(contentClip).helper; }
        public function get questmarkLocation():* { return Object(contentClip).questmarkLocation; }
    }
}
