package mico.appearance
{
   import avatar.Avatar;
   import avatar.AvatarManager;
   import avatar.AvatarWorldView;
   import avatar.NameBar;
   import com.sbi.popup.SBOkPopup;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Loader;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.filters.ColorMatrixFilter;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.net.FileFilter;
   import flash.net.FileReference;
   import flash.net.SharedObject;
   import flash.net.SharedObjectFlushStatus;
   import flash.system.LoaderContext;
   import flash.ui.Mouse;
   import flash.ui.MouseCursor;
   import flash.utils.ByteArray;
   import flash.utils.Dictionary;
   import flash.utils.Endian;
   import flash.utils.clearTimeout;
   import flash.utils.setTimeout;
   import gui.GuiManager;

   public final class MicoAppearanceImages
   {
      public static const PLATE_REFERENCE:String = "512 x 128";
      public static const BADGE_REFERENCE:String = "128 x 128";
      private static const MAX_BYTES:uint = 2 * 1024 * 1024;
      private static const MAX_INPUT_SIDE:int = 2048;
      private static const PLATE_WIDTH:int = 128;
      private static const PLATE_HEIGHT:int = 48;
      private static const BADGE_SIDE:int = 48;
      private static const READ_TIMEOUT_MS:int = 15000;
      private static const LIGHT_NAME_COLOR:uint = 0xfff9ee;
      private static const DARK_NAME_COLOR:uint = 0x1f150f;

      private static var profileName:String = "";
      private static var profile:SharedObject;
      private static var pictures:Object = {};
      private static var activeBar:NameBar;
      private static var plateArt:Sprite;
      private static var badgeArt:Sprite;
      private static var originalBadges:Dictionary = new Dictionary(true);
      private static var contrastedName:DisplayObject;
      private static var nameColorMatrix:Array;

      private static var picker:FileReference;
      private static var decoder:Loader;
      private static var pendingKind:String;
      private static var pendingUser:String;
      private static var readTimer:uint;
      private static var cursorBeforePicker:String;
      private static var restoreCursorTimer:uint;

      public static function handleAction(action:String) : void
      {
         if(pendingKind != null)
         {
            return;
         }
         var username:String = ownUsername();
         if(username == "")
         {
            message("Entre com sua conta para personalizar a placa.");
            return;
         }
         useProfile(username);
         switch(action)
         {
            case "plate":
            case "badge":
               chooseImage(action,username);
               break;
            case "reset-plate":
               applyImage("plate",null);
               break;
            case "reset-badge":
               applyImage("badge",null);
               break;
         }
      }

      public static function track(bar:NameBar, model:Object) : void
      {
         var avatar:Avatar = model as Avatar;
         if(!(bar.parent is AvatarWorldView) || avatar == null || avatar.userName == null)
         {
            return;
         }
         var username:String = ownUsername();
         if(username != "" && avatar.userName.toLowerCase() == username)
         {
            useProfile(username);
            if(activeBar != bar)
            {
               bind(bar);
            }
         }
      }

      public static function detach(bar:NameBar) : void
      {
         if(bar == activeBar)
         {
            clearArt();
            activeBar = null;
         }
      }

      public static function refresh(bar:NameBar) : void
      {
         if(bar == null || bar != activeBar)
         {
            return;
         }
         clearArt();
         try
         {
            if(pictures.plate != null)
            {
               drawPlate(bar,BitmapData(pictures.plate));
            }
            if(pictures.badge != null)
            {
               drawBadge(bar,BitmapData(pictures.badge));
            }
         }
         catch(error:Error)
         {
            // A different HUD asset may not have the stock plate parts.
            clearArt();
         }
      }

      private static function bind(bar:NameBar) : void
      {
         if(activeBar != bar)
         {
            clearArt();
            activeBar = bar;
         }
         refresh(bar);
      }

      private static function ownUsername() : String
      {
         if(gMainFrame == null || gMainFrame.userInfo == null || gMainFrame.userInfo.myUserName == null)
         {
            return "";
         }
         return gMainFrame.userInfo.myUserName.toLowerCase();
      }

      private static function useProfile(username:String) : void
      {
         if(profileName == username)
         {
            return;
         }
         clearArt();
         activeBar = null;
         for each(var oldImage:BitmapData in pictures)
         {
            oldImage.dispose();
         }
         pictures = {};
         profileName = username;
         profile = null;
         try
         {
            if(/^[a-z0-9_-]{1,32}$/.test(username))
            {
               profile = SharedObject.getLocal("mico_appearance_v1_" + username,"/");
               readSaved("plate",PLATE_WIDTH,PLATE_HEIGHT);
               readSaved("badge",BADGE_SIDE,BADGE_SIDE);
            }
         }
         catch(error:Error)
         {
            profile = null;
         }
      }

      private static function readSaved(kind:String, maxWidth:int, maxHeight:int) : void
      {
         var saved:Object = profile.data[kind];
         if(saved == null)
         {
            return;
         }
         var width:int = int(saved.width);
         var height:int = int(saved.height);
         var pixels:ByteArray = saved.pixels as ByteArray;
         if(width < 1 || height < 1 || width > maxWidth || height > maxHeight || pixels == null || pixels.length != width * height * 4)
         {
            return;
         }
         pixels.position = 0;
         pixels.endian = Endian.BIG_ENDIAN;
         var image:BitmapData = new BitmapData(width,height,true,0);
         image.setPixels(image.rect,pixels);
         pictures[kind] = image;
      }

      private static function chooseImage(kind:String, username:String) : void
      {
         pendingKind = kind;
         pendingUser = username;
         try
         {
            preparePickerCursor();
            picker = new FileReference();
            picker.addEventListener(Event.SELECT,onFileSelected);
            picker.addEventListener(Event.CANCEL,onFileCancelled);
            picker.addEventListener(Event.COMPLETE,onFileRead);
            picker.addEventListener(IOErrorEvent.IO_ERROR,onReadError);
            picker.addEventListener(SecurityErrorEvent.SECURITY_ERROR,onReadError);
            var reference:String = kind == "plate" ? PLATE_REFERENCE : BADGE_REFERENCE;
            var filter:FileFilter = new FileFilter("PNG/JPG (ideal: " + reference + " px)","*.png;*.jpg;*.jpeg");
            if(!picker.browse([filter]))
            {
               finishRead();
            }
         }
         catch(error:Error)
         {
            failRead("Não foi possível abrir o seletor de arquivos.");
         }
      }

      private static function onFileSelected(event:Event) : void
      {
         try
         {
            if(picker.size <= 0 || picker.size > MAX_BYTES)
            {
               failRead("Escolha uma imagem PNG ou JPG de até 2 MB.");
               return;
            }
            readTimer = setTimeout(onReadTimeout,READ_TIMEOUT_MS);
            picker.load();
         }
         catch(error:Error)
         {
            failRead("Não foi possível ler a imagem escolhida.");
         }
      }

      private static function onFileCancelled(event:Event) : void
      {
         finishRead();
      }

      private static function onReadError(event:Event) : void
      {
         failRead("Não foi possível abrir a imagem escolhida.");
      }

      private static function onReadTimeout() : void
      {
         failRead("A leitura demorou demais. Escolha a imagem novamente.");
      }

      private static function onFileRead(event:Event) : void
      {
         try
         {
            var bytes:ByteArray = picker.data;
            releasePicker(false);
            if(!isSupportedImage(bytes))
            {
               failRead("Use um PNG ou JPG válido de até 2048 × 2048 pixels.");
               return;
            }
            decoder = new Loader();
            decoder.contentLoaderInfo.addEventListener(Event.COMPLETE,onDecoded);
            decoder.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,onReadError);
            decoder.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,onReadError);
            var context:LoaderContext = new LoaderContext(false);
            if("allowCodeImport" in context)
            {
               context["allowCodeImport"] = false;
            }
            bytes.position = 0;
            decoder.loadBytes(bytes,context);
         }
         catch(error:Error)
         {
            failRead("Não foi possível decodificar a imagem.");
         }
      }

      // Read dimensions before invoking the Flash decoder. A renamed SWF,
      // an oversized image and a truncated header all stop here.
      private static function isSupportedImage(bytes:ByteArray) : Boolean
      {
         if(bytes == null || bytes.length < 11 || bytes.length > MAX_BYTES)
         {
            return false;
         }
         bytes.endian = Endian.BIG_ENDIAN;
         bytes.position = 0;
         if(bytes.length >= 33 && bytes.readUnsignedInt() == 0x89504e47 && bytes.readUnsignedInt() == 0x0d0a1a0a)
         {
            return bytes.readUnsignedInt() == 13 && bytes.readUnsignedInt() == 0x49484452 && validSize(bytes.readUnsignedInt(),bytes.readUnsignedInt());
         }
         bytes.position = 0;
         if(bytes.readUnsignedShort() != 0xffd8)
         {
            return false;
         }
         while(bytes.bytesAvailable >= 4)
         {
            if(bytes.readUnsignedByte() != 0xff)
            {
               return false;
            }
            var marker:int = bytes.readUnsignedByte();
            while(marker == 0xff && bytes.bytesAvailable > 0)
            {
               marker = bytes.readUnsignedByte();
            }
            if(marker == 0xda || marker == 0xd9 || bytes.bytesAvailable < 2)
            {
               return false;
            }
            var size:int = bytes.readUnsignedShort();
            if(size < 2 || size - 2 > bytes.bytesAvailable)
            {
               return false;
            }
            if(marker == 0xc0 || marker == 0xc1 || marker == 0xc2)
            {
               if(size < 8 || bytes.readUnsignedByte() != 8)
               {
                  return false;
               }
               return validSize(bytes.readUnsignedShort(),bytes.readUnsignedShort());
            }
            bytes.position += size - 2;
         }
         return false;
      }

      private static function validSize(width:uint, height:uint) : Boolean
      {
         return width > 0 && height > 0 && width <= MAX_INPUT_SIDE && height <= MAX_INPUT_SIDE;
      }

      private static function onDecoded(event:Event) : void
      {
         var kind:String = pendingKind;
         var username:String = pendingUser;
         var image:BitmapData;
         try
         {
            var bitmap:Bitmap = decoder.content as Bitmap;
            if(bitmap == null || !validSize(bitmap.bitmapData.width,bitmap.bitmapData.height))
            {
               failRead("A imagem escolhida não é compatível.");
               return;
            }
            var width:int = kind == "plate" ? PLATE_WIDTH : BADGE_SIDE;
            var height:int = kind == "plate" ? PLATE_HEIGHT : BADGE_SIDE;
            var scale:Number = Math.min(1,width / bitmap.bitmapData.width,height / bitmap.bitmapData.height);
            var outputWidth:int = Math.max(1,Math.round(bitmap.bitmapData.width * scale));
            var outputHeight:int = Math.max(1,Math.round(bitmap.bitmapData.height * scale));
            image = new BitmapData(outputWidth,outputHeight,true,0);
            var transform:Matrix = new Matrix(outputWidth / bitmap.bitmapData.width,0,0,outputHeight / bitmap.bitmapData.height);
            image.draw(bitmap.bitmapData,transform,null,null,null,true);
         }
         catch(error:Error)
         {
            if(image != null)
            {
               image.dispose();
            }
            failRead("Não foi possível preparar a imagem para a placa.");
            return;
         }
         finishRead();
         if(username != ownUsername())
         {
            image.dispose();
            return;
         }
         useProfile(username);
         applyImage(kind,image);
      }

      private static function releasePicker(cancel:Boolean) : void
      {
         var file:FileReference = picker;
         picker = null;
         if(file == null)
         {
            return;
         }
         file.removeEventListener(Event.SELECT,onFileSelected);
         file.removeEventListener(Event.CANCEL,onFileCancelled);
         file.removeEventListener(Event.COMPLETE,onFileRead);
         file.removeEventListener(IOErrorEvent.IO_ERROR,onReadError);
         file.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,onReadError);
         if(cancel)
         {
            try
            {
               file.cancel();
            }
            catch(error:Error)
            {
               // FileReference may already have ended the operation.
            }
         }
      }

      private static function finishRead(cancel:Boolean = false) : void
      {
         clearTimeout(readTimer);
         readTimer = 0;
         releasePicker(cancel);
         if(decoder != null)
         {
            decoder.contentLoaderInfo.removeEventListener(Event.COMPLETE,onDecoded);
            decoder.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,onReadError);
            decoder.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,onReadError);
            var completed:Loader = decoder;
            decoder = null;
            try
            {
               completed.unload();
            }
            catch(error:Error)
            {
               // It may have failed before it produced any content.
            }
         }
         pendingKind = null;
         pendingUser = null;
         restoreCursorAfterPicker();
      }

      private static function preparePickerCursor() : void
      {
         if(restoreCursorTimer != 0)
         {
            clearTimeout(restoreCursorTimer);
            restoreGameCursor();
         }
         cursorBeforePicker = Mouse.cursor;
         Mouse.cursor = MouseCursor.AUTO;
         Mouse.show();
      }

      private static function restoreCursorAfterPicker() : void
      {
         if(cursorBeforePicker == null)
         {
            return;
         }
         clearTimeout(restoreCursorTimer);
         Mouse.cursor = MouseCursor.ARROW;
         Mouse.show();
         // Give the native dialog a chance to return focus to the game.
         restoreCursorTimer = setTimeout(restoreGameCursor,80);
      }

      private static function restoreGameCursor() : void
      {
         restoreCursorTimer = 0;
         var cursor:String = cursorBeforePicker;
         cursorBeforePicker = null;
         if(cursor == null)
         {
            return;
         }
         try
         {
            Mouse.cursor = cursor;
         }
         catch(error:Error)
         {
            Mouse.cursor = MouseCursor.AUTO;
         }
         Mouse.show();
      }

      private static function failRead(text:String) : void
      {
         finishRead(true);
         message(text);
      }

      private static function applyImage(kind:String, image:BitmapData) : void
      {
         clearArt();
         var old:BitmapData = pictures[kind] as BitmapData;
         if(old != null)
         {
            old.dispose();
         }
         if(image == null)
         {
            delete pictures[kind];
         }
         else
         {
            pictures[kind] = image;
         }
         var player:AvatarWorldView = AvatarManager.playerAvatarWorldView;
         bind(player == null ? null : player.nameBar);
         var saved:Boolean = saveImage(kind,image);
         if(image != null && activeBar != null && (kind == "plate" ? plateArt == null : badgeArt == null))
         {
            message("O arquivo foi lido, mas a imagem não pôde ser exibida nesta placa.");
         }
         else if(!saved)
         {
            message("O visual mudou nesta sessão. O salvamento local não foi confirmado.");
         }
      }

      private static function saveImage(kind:String, image:BitmapData) : Boolean
      {
         if(profile == null)
         {
            return false;
         }
         try
         {
            if(image == null)
            {
               delete profile.data[kind];
            }
            else
            {
               profile.data[kind] = {width:image.width,height:image.height,pixels:image.getPixels(image.rect)};
            }
            return profile.flush() == SharedObjectFlushStatus.FLUSHED;
         }
         catch(error:Error)
         {
            return false;
         }
      }

      private static function clearArt() : void
      {
         clearNameContrast();
         if(plateArt != null && plateArt.parent != null)
         {
            plateArt.parent.removeChild(plateArt);
         }
         if(badgeArt != null && badgeArt.parent != null)
         {
            badgeArt.parent.removeChild(badgeArt);
         }
         for(var icon:Object in originalBadges)
         {
            icon.visible = originalBadges[icon];
            delete originalBadges[icon];
         }
         plateArt = null;
         badgeArt = null;
      }

      private static function drawPlate(bar:NameBar, image:BitmapData) : void
      {
         var left:DisplayObject = bar["e"] as DisplayObject;
         var middle:DisplayObject = bar["m"] as DisplayObject;
         var nameClip:DisplayObject = bar["c"] as DisplayObject;
         var label:DisplayObject = childInBar(bar,nameClip);
         if(left == null || middle == null || label == null)
         {
            return;
         }
         var center:Rectangle = middle.getBounds(bar);
         var area:Rectangle = left.getBounds(bar).union(center);
         area.inflate(-0.8,-0.8);
         if(area.width <= 1 || area.height <= 1)
         {
            return;
         }

         // Paint one continuous surface across both timeline pieces. The
         // left cap is an ellipse cut in half, joined to the rectangular bar.
         var join:Number = Math.max(area.left,Math.min(area.right,center.left));
         var middleY:Number = area.top + area.height / 2;
         var controlX:Number = (join - area.left) * 0.55228475;
         var controlY:Number = area.height / 2 * 0.55228475;
         var fill:Matrix = new Matrix(area.width / image.width,0,0,area.height / image.height,area.x,area.y);
         plateArt = new Sprite();
         plateArt.mouseEnabled = false;
         plateArt.mouseChildren = false;
         plateArt.graphics.beginBitmapFill(image,fill,false,true);
         plateArt.graphics.moveTo(area.right,area.top);
         plateArt.graphics.lineTo(join,area.top);
         plateArt.graphics.cubicCurveTo(join - controlX,area.top,area.left,middleY - controlY,area.left,middleY);
         plateArt.graphics.cubicCurveTo(area.left,middleY + controlY,join - controlX,area.bottom,join,area.bottom);
         plateArt.graphics.lineTo(area.right,area.bottom);
         plateArt.graphics.lineTo(area.right,area.top);
         plateArt.graphics.endFill();
         var index:int = bar.getChildIndex(label);
         var emblem:DisplayObject = childInBar(bar,bar["selnub"] as DisplayObject);
         if(emblem != null)
         {
            index = Math.min(index,bar.getChildIndex(emblem));
         }
         bar.addChildAt(plateArt,index);
         applyNameContrast(nameClip.getBounds(bar),area,image,nameClip);
      }

      private static function applyNameContrast(nameBounds:Rectangle, plateBounds:Rectangle, image:BitmapData, nameClip:DisplayObject) : void
      {
         var sampleArea:Rectangle = nameBounds.intersection(plateBounds);
         if(sampleArea.isEmpty())
         {
            return;
         }

         // Sample the displayed part of the image behind the name. Using
         // the majority avoids a small, very bright detail dominating a dark photo.
         var columns:int = 12;
         var rows:int = 5;
         var opacity:Number = 0;
         var brightWeight:Number = 0;
         var threshold:Number = Math.sqrt((luminance(LIGHT_NAME_COLOR) + 0.05) * (luminance(DARK_NAME_COLOR) + 0.05)) - 0.05;
         for(var row:int = 0; row < rows; row++)
         {
            var y:Number = sampleArea.y + (row + 0.5) * sampleArea.height / rows;
            var py:int = Math.min(image.height - 1,Math.max(0,int((y - plateBounds.y) / plateBounds.height * image.height)));
            for(var column:int = 0; column < columns; column++)
            {
               var x:Number = sampleArea.x + (column + 0.5) * sampleArea.width / columns;
               var px:int = Math.min(image.width - 1,Math.max(0,int((x - plateBounds.x) / plateBounds.width * image.width)));
               var pixel:uint = image.getPixel32(px,py);
               var alpha:Number = (pixel >>> 24) / 255;
               opacity += alpha;
               if(alpha > 0 && luminance(pixel) >= threshold)
               {
                  brightWeight += alpha;
               }
            }
         }
         if(opacity < columns * rows / 2)
         {
            // The underlying nameplate is still the main background.
            return;
         }

         var color:uint = brightWeight >= opacity / 2 ? DARK_NAME_COLOR : LIGHT_NAME_COLOR;
         var matrix:Array = [
            0,0,0,0,(color >> 16) & 255,
            0,0,0,0,(color >> 8) & 255,
            0,0,0,0,color & 255,
            0,0,0,1,0
         ];
         // Recolor the whole name clip after the HUD's nested palette tint.
         nameClip.filters = nameClip.filters.concat([new ColorMatrixFilter(matrix)]);
         contrastedName = nameClip;
         nameColorMatrix = matrix;
      }

      private static function clearNameContrast() : void
      {
         if(contrastedName == null)
         {
            return;
         }
         var filters:Array = contrastedName.filters;
         var last:ColorMatrixFilter = filters.length > 0 ? filters[filters.length - 1] as ColorMatrixFilter : null;
         if(last != null && last.matrix.join(",") == nameColorMatrix.join(","))
         {
            filters.pop();
            contrastedName.filters = filters;
         }
         contrastedName = null;
         nameColorMatrix = null;
      }

      private static function luminance(rgb:uint) : Number
      {
         return 0.2126 * linearChannel((rgb >> 16) & 255)
              + 0.7152 * linearChannel((rgb >> 8) & 255)
              + 0.0722 * linearChannel(rgb & 255);
      }

      private static function linearChannel(value:uint) : Number
      {
         var channel:Number = value / 255;
         return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055,2.4);
      }

      private static function childInBar(bar:NameBar, part:DisplayObject) : DisplayObject
      {
         while(part != null && part.parent != bar)
         {
            part = part.parent;
         }
         return part;
      }

      private static function drawBadge(bar:NameBar, image:BitmapData) : void
      {
         var nub:DisplayObjectContainer = bar["selnub"] as DisplayObjectContainer;
         if(nub == null || !nub.visible)
         {
            return;
         }
         var face:DisplayObjectContainer = nub.getChildByName("nub") as DisplayObjectContainer;
         var states:DisplayObjectContainer = face != null ? face.getChildByName("mouse") as DisplayObjectContainer : null;
         var normal:DisplayObjectContainer = states != null ? states.getChildByName("up") as DisplayObjectContainer : null;
         var interior:DisplayObject = normal != null ? normal.getChildByName("gradient") : null;
         var area:Rectangle = interior != null ? interior.getBounds(bar) : (face != null ? face.getBounds(bar) : nub.getBounds(bar));
         var side:Number = Math.min(area.width,area.height);
         // The member HUD exposes the precise inner disc. Other models use
         // an inset relative to the visible emblem, leaving the native rim.
         side = interior != null ? side - 0.8 : side * 0.78;
         if(side <= 1)
         {
            return;
         }
         var centerX:Number = area.x + area.width / 2;
         var centerY:Number = area.y + area.height / 2;
         var scale:Number = Math.max(side / image.width,side / image.height);
         var fill:Matrix = new Matrix(scale,0,0,scale,centerX - image.width * scale / 2,centerY - image.height * scale / 2);
         badgeArt = new Sprite();
         badgeArt.mouseEnabled = false;
         badgeArt.mouseChildren = false;
         badgeArt.graphics.beginBitmapFill(image,fill,false,true);
         badgeArt.graphics.drawCircle(centerX,centerY,side / 2);
         badgeArt.graphics.endFill();
         bar.addChild(badgeArt);

         if(states != null)
         {
            for each(var stateName:String in ["up","mouse"])
            {
               var state:DisplayObjectContainer = states.getChildByName(stateName) as DisplayObjectContainer;
               var icon:DisplayObject = state != null ? state.getChildByName("light") : null;
               if(icon != null)
               {
                  originalBadges[icon] = icon.visible;
                  icon.visible = false;
               }
            }
         }
      }

      private static function message(text:String) : void
      {
         if(GuiManager.guiLayer != null)
         {
            new SBOkPopup(GuiManager.guiLayer,text);
         }
      }
   }
}
