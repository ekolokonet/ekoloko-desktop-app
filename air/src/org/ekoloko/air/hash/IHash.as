/**
 * IHash
 * 
 * An interface for each hash function to implement
 * Copyright (c) 2007 Henri Torgemane
 * 
 * See LICENSE.txt for full license information.
 */
package org.ekoloko.air.hash
{
	import flash.utils.ByteArray;

	public interface IHash
	{
		function getInputSize():uint;
		function getHashSize():uint;
		function hash(src:ByteArray):ByteArray;
		function toString():String;
		function getPadSize():int;
	}
}