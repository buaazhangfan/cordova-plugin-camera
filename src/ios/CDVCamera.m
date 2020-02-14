/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVCamera.h"
#import "CDVJpegHeaderWriter.h"
#import "UIImage+CropScaleOrientation.h"
#import <ImageIO/CGImageProperties.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>
#import <ImageIO/CGImageDestination.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <objc/message.h>

#ifndef __CORDOVA_4_0_0
    #import <Cordova/NSData+Base64.h>
#endif

#define CDV_PHOTO_PREFIX @"cdv_photo_"

static NSSet* org_apache_cordova_validArrowDirections;

static NSString* toBase64(NSData* data) {
    SEL s1 = NSSelectorFromString(@"cdv_base64EncodedString");
    SEL s2 = NSSelectorFromString(@"base64EncodedString");
    SEL s3 = NSSelectorFromString(@"base64EncodedStringWithOptions:");

    if ([data respondsToSelector:s1]) {
        NSString* (*func)(id, SEL) = (void *)[data methodForSelector:s1];
        return func(data, s1);
    } else if ([data respondsToSelector:s2]) {
        NSString* (*func)(id, SEL) = (void *)[data methodForSelector:s2];
        return func(data, s2);
    } else if ([data respondsToSelector:s3]) {
        NSString* (*func)(id, SEL, NSUInteger) = (void *)[data methodForSelector:s3];
        return func(data, s3, 0);
    } else {
        return nil;
    }
}

@implementation CDVPictureOptions

+ (instancetype) createFromTakePictureArguments:(CDVInvokedUrlCommand*)command
{
    CDVPictureOptions* pictureOptions = [[CDVPictureOptions alloc] init];

    pictureOptions.quality = [command argumentAtIndex:0 withDefault:@(50)];
    pictureOptions.destinationType = [[command argumentAtIndex:1 withDefault:@(DestinationTypeFileUri)] unsignedIntegerValue];
    pictureOptions.sourceType = [[command argumentAtIndex:2 withDefault:@(UIImagePickerControllerSourceTypeCamera)] unsignedIntegerValue];

    NSNumber* targetWidth = [command argumentAtIndex:3 withDefault:nil];
    NSNumber* targetHeight = [command argumentAtIndex:4 withDefault:nil];
    pictureOptions.targetSize = CGSizeMake(0, 0);
    if ((targetWidth != nil) && (targetHeight != nil)) {
        pictureOptions.targetSize = CGSizeMake([targetWidth floatValue], [targetHeight floatValue]);
    }

    pictureOptions.encodingType = [[command argumentAtIndex:5 withDefault:@(EncodingTypeJPEG)] unsignedIntegerValue];
    pictureOptions.mediaType = [[command argumentAtIndex:6 withDefault:@(MediaTypePicture)] unsignedIntegerValue];
    pictureOptions.allowsEditing = [[command argumentAtIndex:7 withDefault:@(NO)] boolValue];
    pictureOptions.correctOrientation = [[command argumentAtIndex:8 withDefault:@(NO)] boolValue];
    pictureOptions.saveToPhotoAlbum = [[command argumentAtIndex:9 withDefault:@(NO)] boolValue];
    pictureOptions.popoverOptions = [command argumentAtIndex:10 withDefault:nil];
    pictureOptions.cameraDirection = [[command argumentAtIndex:11 withDefault:@(UIImagePickerControllerCameraDeviceRear)] unsignedIntegerValue];
    
    pictureOptions.cardScan = [[command argumentAtIndex:12 withDefault:@(NO)] boolValue];
    
    pictureOptions.popoverSupported = NO;
    pictureOptions.usesGeolocation = YES;
    
    return pictureOptions;
}

@end


@interface CDVCamera ()

@property (readwrite, assign) BOOL hasPendingOperation;

@end

@implementation CDVCamera

+ (void)initialize
{
    org_apache_cordova_validArrowDirections = [[NSSet alloc] initWithObjects:[NSNumber numberWithInt:UIPopoverArrowDirectionUp], [NSNumber numberWithInt:UIPopoverArrowDirectionDown], [NSNumber numberWithInt:UIPopoverArrowDirectionLeft], [NSNumber numberWithInt:UIPopoverArrowDirectionRight], [NSNumber numberWithInt:UIPopoverArrowDirectionAny], nil];
}

@synthesize hasPendingOperation, pickerController, locationManager;

- (NSURL*) urlTransformer:(NSURL*)url
{
    NSURL* urlToTransform = url;

    // for backwards compatibility - we check if this property is there
    SEL sel = NSSelectorFromString(@"urlTransformer");
    if ([self.commandDelegate respondsToSelector:sel]) {
        // grab the block from the commandDelegate
        NSURL* (^urlTransformer)(NSURL*) = ((id(*)(id, SEL))objc_msgSend)(self.commandDelegate, sel);
        // if block is not null, we call it
        if (urlTransformer) {
            urlToTransform = urlTransformer(url);
        }
    }

    return urlToTransform;
}

- (BOOL)usesGeolocation
{
    id useGeo = [self.commandDelegate.settings objectForKey:[@"CameraUsesGeolocation" lowercaseString]];
    return [(NSNumber*)useGeo boolValue];
}

- (BOOL)popoverSupported
{
    return (NSClassFromString(@"UIPopoverController") != nil) &&
           (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
}

- (void)takePicture:(CDVInvokedUrlCommand*)command
{
    self.hasPendingOperation = YES;
    __weak CDVCamera* weakSelf = self;

    [self.commandDelegate runInBackground:^{
        CDVPictureOptions* pictureOptions = [CDVPictureOptions createFromTakePictureArguments:command];
        pictureOptions.popoverSupported = [weakSelf popoverSupported];
        pictureOptions.usesGeolocation = [weakSelf usesGeolocation];
        pictureOptions.cropToSize = NO;

        BOOL hasCamera = [UIImagePickerController isSourceTypeAvailable:pictureOptions.sourceType];
        if (!hasCamera) {
            NSLog(@"Camera.getPicture: source type %lu not available.", (unsigned long)pictureOptions.sourceType);
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No camera available"];
            [weakSelf.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        // Validate the app has permission to access the camera
        if (pictureOptions.sourceType == UIImagePickerControllerSourceTypeCamera) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted)
             {
                 if(!granted)
                 {
                     // Denied; show an alert
                     dispatch_async(dispatch_get_main_queue(), ^{
                         UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] message:NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.", nil) preferredStyle:UIAlertControllerStyleAlert];
                         [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                             [weakSelf sendNoPermissionResult:command.callbackId];
                         }]];
                         [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                             [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                             [weakSelf sendNoPermissionResult:command.callbackId];
                         }]];
                         [weakSelf.viewController presentViewController:alertController animated:YES completion:nil];
                     });
                 } else {
                     [weakSelf showCameraPicker:command.callbackId withOptions:pictureOptions];
                 }
             }];
        } else {
            [weakSelf showCameraPicker:command.callbackId withOptions:pictureOptions];
        }
    }];
}

- (void)showCameraPicker:(NSString*)callbackId withOptions:(CDVPictureOptions *) pictureOptions
{
    CDVCameraPicker* cameraPicker = [CDVCameraPicker createFromPictureOptions:pictureOptions];
    self.pickerController = cameraPicker;

    cameraPicker.delegate = self;
    cameraPicker.callbackId = callbackId;
    // we need to capture this state for memory warnings that dealloc this object
    cameraPicker.webView = self.webView;
    // Perform UI operations on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        // If a popover is already open, close it; we only want one at a time.
        if (([[self pickerController] pickerPopoverController] != nil) && [[[self pickerController] pickerPopoverController] isPopoverVisible]) {
            [[[self pickerController] pickerPopoverController] dismissPopoverAnimated:YES];
            [[[self pickerController] pickerPopoverController] setDelegate:nil];
            [[self pickerController] setPickerPopoverController:nil];
        }

        if ([self popoverSupported] && (pictureOptions.sourceType != UIImagePickerControllerSourceTypeCamera)) {
            if (cameraPicker.pickerPopoverController == nil) {
                cameraPicker.pickerPopoverController = [[NSClassFromString(@"UIPopoverController") alloc] initWithContentViewController:cameraPicker];
            }
            [self displayPopover:pictureOptions.popoverOptions];
            self.hasPendingOperation = NO;
        } else {
            cameraPicker.modalPresentationStyle = UIModalPresentationCurrentContext;
            [self.viewController presentViewController:cameraPicker animated:YES completion:^{
                self.hasPendingOperation = NO;
            }];
        }
    });
}

- (void)sendNoPermissionResult:(NSString*)callbackId
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"has no access to camera"];   // error callback expects string ATM

    [self.commandDelegate sendPluginResult:result callbackId:callbackId];

    self.hasPendingOperation = NO;
    self.pickerController = nil;
}

- (void)repositionPopover:(CDVInvokedUrlCommand*)command
{
    if (([[self pickerController] pickerPopoverController] != nil) && [[[self pickerController] pickerPopoverController] isPopoverVisible]) {

        [[[self pickerController] pickerPopoverController] dismissPopoverAnimated:NO];

        NSDictionary* options = [command argumentAtIndex:0 withDefault:nil];
        [self displayPopover:options];
    }
}

- (NSInteger)integerValueForKey:(NSDictionary*)dict key:(NSString*)key defaultValue:(NSInteger)defaultValue
{
    NSInteger value = defaultValue;

    NSNumber* val = [dict valueForKey:key];  // value is an NSNumber

    if (val != nil) {
        value = [val integerValue];
    }
    return value;
}

- (void)displayPopover:(NSDictionary*)options
{
    NSInteger x = 0;
    NSInteger y = 32;
    NSInteger width = 320;
    NSInteger height = 480;
    UIPopoverArrowDirection arrowDirection = UIPopoverArrowDirectionAny;

    if (options) {
        x = [self integerValueForKey:options key:@"x" defaultValue:0];
        y = [self integerValueForKey:options key:@"y" defaultValue:32];
        width = [self integerValueForKey:options key:@"width" defaultValue:320];
        height = [self integerValueForKey:options key:@"height" defaultValue:480];
        arrowDirection = [self integerValueForKey:options key:@"arrowDir" defaultValue:UIPopoverArrowDirectionAny];
        if (![org_apache_cordova_validArrowDirections containsObject:[NSNumber numberWithUnsignedInteger:arrowDirection]]) {
            arrowDirection = UIPopoverArrowDirectionAny;
        }
    }

    [[[self pickerController] pickerPopoverController] setDelegate:self];
    [[[self pickerController] pickerPopoverController] presentPopoverFromRect:CGRectMake(x, y, width, height)
                                                                 inView:[self.webView superview]
                                               permittedArrowDirections:arrowDirection
                                                               animated:YES];
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if([navigationController isKindOfClass:[UIImagePickerController class]]){
        
        // If popoverWidth and popoverHeight are specified and are greater than 0, then set popover size, else use apple's default popoverSize
        NSDictionary* options = self.pickerController.pictureOptions.popoverOptions;
        if(options) {
            NSInteger popoverWidth = [self integerValueForKey:options key:@"popoverWidth" defaultValue:0];
            NSInteger popoverHeight = [self integerValueForKey:options key:@"popoverHeight" defaultValue:0];
            if(popoverWidth > 0 && popoverHeight > 0)
            {
                [viewController setPreferredContentSize:CGSizeMake(popoverWidth,popoverHeight)];
            }
        }
        
        
        UIImagePickerController* cameraPicker = (UIImagePickerController*)navigationController;

        if(![cameraPicker.mediaTypes containsObject:(NSString*)kUTTypeImage]){
            [viewController.navigationItem setTitle:NSLocalizedString(@"Videos", nil)];
        }
    }
}

- (void)cleanup:(CDVInvokedUrlCommand*)command
{
    // empty the tmp directory
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSError* err = nil;
    BOOL hasErrors = NO;

    // clear contents of NSTemporaryDirectory
    NSString* tempDirectoryPath = NSTemporaryDirectory();
    NSDirectoryEnumerator* directoryEnumerator = [fileMgr enumeratorAtPath:tempDirectoryPath];
    NSString* fileName = nil;
    BOOL result;

    while ((fileName = [directoryEnumerator nextObject])) {
        // only delete the files we created
        if (![fileName hasPrefix:CDV_PHOTO_PREFIX]) {
            continue;
        }
        NSString* filePath = [tempDirectoryPath stringByAppendingPathComponent:fileName];
        result = [fileMgr removeItemAtPath:filePath error:&err];
        if (!result && err) {
            NSLog(@"Failed to delete: %@ (error: %@)", filePath, err);
            hasErrors = YES;
        }
    }

    CDVPluginResult* pluginResult;
    if (hasErrors) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:@"One or more files failed to be deleted."];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)popoverControllerDidDismissPopover:(id)popoverController
{
    UIPopoverController* pc = (UIPopoverController*)popoverController;

    [pc dismissPopoverAnimated:YES];
    pc.delegate = nil;
    if (self.pickerController && self.pickerController.callbackId && self.pickerController.pickerPopoverController) {
        self.pickerController.pickerPopoverController = nil;
        NSString* callbackId = self.pickerController.callbackId;
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"no image selected"];   // error callback expects string ATM
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
    self.hasPendingOperation = NO;
}

- (NSData*)processImage:(UIImage*)image info:(NSDictionary*)info options:(CDVPictureOptions*)options
{
    NSData* data = nil;

    switch (options.encodingType) {
        case EncodingTypePNG:
            data = UIImagePNGRepresentation(image);
            break;
        case EncodingTypeJPEG:
        {
            if ((options.allowsEditing == NO) && (options.targetSize.width <= 0) && (options.targetSize.height <= 0) && (options.correctOrientation == NO) && (([options.quality integerValue] == 100) || (options.sourceType != UIImagePickerControllerSourceTypeCamera))){
                // use image unedited as requested , don't resize
                data = UIImageJPEGRepresentation(image, 1.0);
            } else {
                data = UIImageJPEGRepresentation(image, [options.quality floatValue] / 100.0f);
            }

            if (options.usesGeolocation) {
                NSDictionary* controllerMetadata = [info objectForKey:@"UIImagePickerControllerMediaMetadata"];
                if (controllerMetadata) {
                    self.data = data;
                    self.metadata = [[NSMutableDictionary alloc] init];

                    NSMutableDictionary* EXIFDictionary = [[controllerMetadata objectForKey:(NSString*)kCGImagePropertyExifDictionary]mutableCopy];
                    if (EXIFDictionary)	{
                        [self.metadata setObject:EXIFDictionary forKey:(NSString*)kCGImagePropertyExifDictionary];
                    }

                    if (IsAtLeastiOSVersion(@"8.0")) {
                        [[self locationManager] performSelector:NSSelectorFromString(@"requestWhenInUseAuthorization") withObject:nil afterDelay:0];
                    }
                    [[self locationManager] startUpdatingLocation];
                }
            }
        }
            break;
        default:
            break;
    };

    return data;
}

- (NSString*)tempFilePath:(NSString*)extension
{
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe
    NSString* filePath;

    // generate unique file name
    int i = 1;
    do {
        filePath = [NSString stringWithFormat:@"%@/%@%03d.%@", docsPath, CDV_PHOTO_PREFIX, i++, extension];
    } while ([fileMgr fileExistsAtPath:filePath]);

    return filePath;
}

- (UIImage*)retrieveImage:(NSDictionary*)info options:(CDVPictureOptions*)options
{
    // get the image
    UIImage* image = nil;
    if (options.allowsEditing && [info objectForKey:UIImagePickerControllerEditedImage]) {
        image = [info objectForKey:UIImagePickerControllerEditedImage];
    } else {
        image = [info objectForKey:UIImagePickerControllerOriginalImage];
    }

    if (options.correctOrientation) {
        image = [image imageCorrectedForCaptureOrientation];
    }
    
    if (options.cardScan) {
        image = [image imageByCropping];
    }
    
    UIImage* scaledImage = nil;

    if ((options.targetSize.width > 0) && (options.targetSize.height > 0)) {
        // if cropToSize, resize image and crop to target size, otherwise resize to fit target without cropping
        if (options.cropToSize) {
            scaledImage = [image imageByScalingAndCroppingForSize:options.targetSize];
        } else {
            scaledImage = [image imageByScalingNotCroppingForSize:options.targetSize];
        }
    }
    
    return (scaledImage == nil ? image : scaledImage);
}

- (void)resultForImage:(CDVPictureOptions*)options info:(NSDictionary*)info completion:(void (^)(CDVPluginResult* res))completion
{
    CDVPluginResult* result = nil;
    BOOL saveToPhotoAlbum = options.saveToPhotoAlbum;
    UIImage* image = nil;

    switch (options.destinationType) {
        case DestinationTypeNativeUri:
        {
            NSURL* url = [info objectForKey:UIImagePickerControllerReferenceURL];
            saveToPhotoAlbum = NO;
            // If, for example, we use sourceType = Camera, URL might be nil because image is stored in memory.
            // In this case we must save image to device before obtaining an URI.
            if (url == nil) {
                image = [self retrieveImage:info options:options];
                ALAssetsLibrary* library = [ALAssetsLibrary new];
                [library writeImageToSavedPhotosAlbum:image.CGImage orientation:(ALAssetOrientation)(image.imageOrientation) completionBlock:^(NSURL *assetURL, NSError *error) {
                    CDVPluginResult* resultToReturn = nil;
                    if (error) {
                        resultToReturn = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[error localizedDescription]];
                    } else {
                        NSString* nativeUri = [[self urlTransformer:assetURL] absoluteString];
                        resultToReturn = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:nativeUri];
                    }
                    completion(resultToReturn);
                }];
                return;
            } else {
                NSString* nativeUri = [[self urlTransformer:url] absoluteString];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:nativeUri];
            }
        }
            break;
        case DestinationTypeFileUri:
        {
            image = [self retrieveImage:info options:options];
            NSData* data = [self processImage:image info:info options:options];
            if (data) {

                NSString* extension = options.encodingType == EncodingTypePNG? @"png" : @"jpg";
                NSString* filePath = [self tempFilePath:extension];
                NSError* err = nil;

                // save file
                if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                    result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                } else {
                    result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[[self urlTransformer:[NSURL fileURLWithPath:filePath]] absoluteString]];
                }
            }
        }
            break;
        case DestinationTypeDataUrl:
        {
            image = [self retrieveImage:info options:options];
            NSData* data = [self processImage:image info:info options:options];
            if (data)  {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:toBase64(data)];
            }
        }
            break;
        default:
            break;
    };

    if (saveToPhotoAlbum && image) {
        ALAssetsLibrary* library = [ALAssetsLibrary new];
        [library writeImageToSavedPhotosAlbum:image.CGImage orientation:(ALAssetOrientation)(image.imageOrientation) completionBlock:nil];
    }

    completion(result);
}

- (CDVPluginResult*)resultForVideo:(NSDictionary*)info
{
    NSString* moviePath = [[info objectForKey:UIImagePickerControllerMediaURL] absoluteString];
    return [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:moviePath];
}

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    __weak CDVCameraPicker* cameraPicker = (CDVCameraPicker*)picker;
    __weak CDVCamera* weakSelf = self;

    dispatch_block_t invoke = ^(void) {
        __block CDVPluginResult* result = nil;

        NSString* mediaType = [info objectForKey:UIImagePickerControllerMediaType];
        if ([mediaType isEqualToString:(NSString*)kUTTypeImage]) {
            [weakSelf resultForImage:cameraPicker.pictureOptions info:info completion:^(CDVPluginResult* res) {
                if (![self usesGeolocation] || picker.sourceType != UIImagePickerControllerSourceTypeCamera) {
                    [weakSelf.commandDelegate sendPluginResult:res callbackId:cameraPicker.callbackId];
                    weakSelf.hasPendingOperation = NO;
                    weakSelf.pickerController = nil;
                }
            }];
        }
        else {
            result = [weakSelf resultForVideo:info];
            [weakSelf.commandDelegate sendPluginResult:result callbackId:cameraPicker.callbackId];
            weakSelf.hasPendingOperation = NO;
            weakSelf.pickerController = nil;
        }
    };

    if (cameraPicker.pictureOptions.popoverSupported && (cameraPicker.pickerPopoverController != nil)) {
        [cameraPicker.pickerPopoverController dismissPopoverAnimated:YES];
        cameraPicker.pickerPopoverController.delegate = nil;
        cameraPicker.pickerPopoverController = nil;
        invoke();
    } else {
        [[cameraPicker presentingViewController] dismissViewControllerAnimated:YES completion:invoke];
    }
}

// older api calls newer didFinishPickingMediaWithInfo
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingImage:(UIImage*)image editingInfo:(NSDictionary*)editingInfo
{
    NSDictionary* imageInfo = [NSDictionary dictionaryWithObject:image forKey:UIImagePickerControllerOriginalImage];

    [self imagePickerController:picker didFinishPickingMediaWithInfo:imageInfo];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
    __weak CDVCameraPicker* cameraPicker = (CDVCameraPicker*)picker;
    __weak CDVCamera* weakSelf = self;

    dispatch_block_t invoke = ^ (void) {
        CDVPluginResult* result;
        if (picker.sourceType == UIImagePickerControllerSourceTypeCamera && [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != ALAuthorizationStatusAuthorized) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"has no access to camera"];
        } else if (picker.sourceType != UIImagePickerControllerSourceTypeCamera && ! IsAtLeastiOSVersion(@"11.0") && [ALAssetsLibrary authorizationStatus] != ALAuthorizationStatusAuthorized) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"has no access to assets"];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No Image Selected"];
        }


        [weakSelf.commandDelegate sendPluginResult:result callbackId:cameraPicker.callbackId];

        weakSelf.hasPendingOperation = NO;
        weakSelf.pickerController = nil;
    };

    [[cameraPicker presentingViewController] dismissViewControllerAnimated:YES completion:invoke];
}

- (CLLocationManager*)locationManager
{
	if (locationManager != nil) {
		return locationManager;
	}

	locationManager = [[CLLocationManager alloc] init];
	[locationManager setDesiredAccuracy:kCLLocationAccuracyNearestTenMeters];
	[locationManager setDelegate:self];

	return locationManager;
}

- (void)locationManager:(CLLocationManager*)manager didUpdateToLocation:(CLLocation*)newLocation fromLocation:(CLLocation*)oldLocation
{
    if (locationManager == nil) {
        return;
    }

    [self.locationManager stopUpdatingLocation];
    self.locationManager = nil;

    NSMutableDictionary *GPSDictionary = [[NSMutableDictionary dictionary] init];

    CLLocationDegrees latitude  = newLocation.coordinate.latitude;
    CLLocationDegrees longitude = newLocation.coordinate.longitude;

    // latitude
    if (latitude < 0.0) {
        latitude = latitude * -1.0f;
        [GPSDictionary setObject:@"S" forKey:(NSString*)kCGImagePropertyGPSLatitudeRef];
    } else {
        [GPSDictionary setObject:@"N" forKey:(NSString*)kCGImagePropertyGPSLatitudeRef];
    }
    [GPSDictionary setObject:[NSNumber numberWithFloat:latitude] forKey:(NSString*)kCGImagePropertyGPSLatitude];

    // longitude
    if (longitude < 0.0) {
        longitude = longitude * -1.0f;
        [GPSDictionary setObject:@"W" forKey:(NSString*)kCGImagePropertyGPSLongitudeRef];
    }
    else {
        [GPSDictionary setObject:@"E" forKey:(NSString*)kCGImagePropertyGPSLongitudeRef];
    }
    [GPSDictionary setObject:[NSNumber numberWithFloat:longitude] forKey:(NSString*)kCGImagePropertyGPSLongitude];

    // altitude
    CGFloat altitude = newLocation.altitude;
    if (!isnan(altitude)){
        if (altitude < 0) {
            altitude = -altitude;
            [GPSDictionary setObject:@"1" forKey:(NSString *)kCGImagePropertyGPSAltitudeRef];
        } else {
            [GPSDictionary setObject:@"0" forKey:(NSString *)kCGImagePropertyGPSAltitudeRef];
        }
        [GPSDictionary setObject:[NSNumber numberWithFloat:altitude] forKey:(NSString *)kCGImagePropertyGPSAltitude];
    }

    // Time and date
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss.SSSSSS"];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [GPSDictionary setObject:[formatter stringFromDate:newLocation.timestamp] forKey:(NSString *)kCGImagePropertyGPSTimeStamp];
    [formatter setDateFormat:@"yyyy:MM:dd"];
    [GPSDictionary setObject:[formatter stringFromDate:newLocation.timestamp] forKey:(NSString *)kCGImagePropertyGPSDateStamp];

    [self.metadata setObject:GPSDictionary forKey:(NSString *)kCGImagePropertyGPSDictionary];
    [self imagePickerControllerReturnImageResult];
}

- (void)locationManager:(CLLocationManager*)manager didFailWithError:(NSError*)error
{
    if (locationManager == nil) {
        return;
    }

    [self.locationManager stopUpdatingLocation];
    self.locationManager = nil;

    [self imagePickerControllerReturnImageResult];
}

- (void)imagePickerControllerReturnImageResult
{
    CDVPictureOptions* options = self.pickerController.pictureOptions;
    CDVPluginResult* result = nil;

    if (self.metadata) {
        CGImageSourceRef sourceImage = CGImageSourceCreateWithData((__bridge CFDataRef)self.data, NULL);
        CFStringRef sourceType = CGImageSourceGetType(sourceImage);

        CGImageDestinationRef destinationImage = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)self.data, sourceType, 1, NULL);
        CGImageDestinationAddImageFromSource(destinationImage, sourceImage, 0, (__bridge CFDictionaryRef)self.metadata);
        CGImageDestinationFinalize(destinationImage);

        CFRelease(sourceImage);
        CFRelease(destinationImage);
    }

    switch (options.destinationType) {
        case DestinationTypeFileUri:
        {
            NSError* err = nil;
            NSString* extension = self.pickerController.pictureOptions.encodingType == EncodingTypePNG ? @"png":@"jpg";
            NSString* filePath = [self tempFilePath:extension];

            // save file
            if (![self.data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
            }
            else {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[[self urlTransformer:[NSURL fileURLWithPath:filePath]] absoluteString]];
            }
        }
            break;
        case DestinationTypeDataUrl:
        {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:toBase64(self.data)];
        }
            break;
        case DestinationTypeNativeUri:
        default:
            break;
    };

    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:self.pickerController.callbackId];
    }

    self.hasPendingOperation = NO;
    self.pickerController = nil;
    self.data = nil;
    self.metadata = nil;

    if (options.saveToPhotoAlbum) {
        ALAssetsLibrary *library = [ALAssetsLibrary new];
        [library writeImageDataToSavedPhotosAlbum:self.data metadata:self.metadata completionBlock:nil];
    }
}

@end

@implementation CDVCameraPicker

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIViewController*)childViewControllerForStatusBarHidden
{
    return nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    SEL sel = NSSelectorFromString(@"setNeedsStatusBarAppearanceUpdate");
    if ([self respondsToSelector:sel]) {
        [self performSelector:sel withObject:nil afterDelay:0];
    }

    [super viewWillAppear:animated];
}

+ (instancetype) createFromPictureOptions:(CDVPictureOptions*)pictureOptions;
{
    CDVCameraPicker* cameraPicker = [[CDVCameraPicker alloc] init];
    cameraPicker.pictureOptions = pictureOptions;
    cameraPicker.sourceType = pictureOptions.sourceType;
    cameraPicker.allowsEditing = pictureOptions.allowsEditing;
    
    if (cameraPicker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        if (pictureOptions.cardScan) {
            // We only allow taking pictures (no video) in this API.
            cameraPicker.mediaTypes = @[(NSString*)kUTTypeImage];
            // We can only set the camera device if we're actually using the camera.
            cameraPicker.cameraDevice = pictureOptions.cameraDirection;
            CGSize screenSize = [[UIScreen mainScreen] bounds].size;
            CGFloat offset = 10.0;
            CGFloat width = screenSize.width;
            CGFloat height = screenSize.height;
            CGFloat previewRatio = 4.0 / 3.0;
            CGFloat previewHeight = width * previewRatio;
            CGSize navigationBarSize = [cameraPicker navigationBar].frame.size;
            CGFloat overlayOffset = navigationBarSize.height + offset;
            OverlayView *overlay = [[OverlayView alloc] initWithFrame:CGRectMake(0, height / 2.0 - previewHeight / 2.0 - overlayOffset, width, previewHeight + offset) isPreview:false];
            OverlayView *previewOverlay = [[OverlayView alloc] initWithFrame:CGRectMake(0, height / 2.0 - previewHeight / 2.0, width, previewHeight) isPreview:true];
            cameraPicker.navigationBarHidden = YES;
            cameraPicker.cameraOverlayView = overlay;
            [[NSNotificationCenter defaultCenter] addObserverForName:@"_UIImagePickerControllerUserDidCaptureItem" object:nil queue:nil usingBlock:^(NSNotification *note) {
                NSLog(@"image captured");
                cameraPicker.cameraOverlayView = previewOverlay;
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:@"_UIImagePickerControllerUserDidRejectItem" object:nil queue:nil usingBlock:^(NSNotification *note) {
                NSLog(@"retake pressed");
                cameraPicker.cameraOverlayView = overlay;
            }];
        } else {
            // We only allow taking pictures (no video) in this API.
            cameraPicker.mediaTypes = @[(NSString*)kUTTypeImage];
            // We can only set the camera device if we're actually using the camera.
            cameraPicker.cameraDevice = pictureOptions.cameraDirection;
        }
    } else if (pictureOptions.mediaType == MediaTypeAll) {
        cameraPicker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:cameraPicker.sourceType];
    } else {
        NSArray* mediaArray = @[(NSString*)(pictureOptions.mediaType == MediaTypeVideo ? kUTTypeMovie : kUTTypeImage)];
        cameraPicker.mediaTypes = mediaArray;
    }

    return cameraPicker;
}

@end

@implementation OverlayView

#define kLineWidth 5
#define kLineLong 35
#define kLineMargin 20
#define kWidth   [UIScreen mainScreen].bounds.size.width
#define kHeight  [UIScreen mainScreen].bounds.size.height
#define kRatio 3./4.

- (void)drawRect:(CGRect)rect {
    UIColor *color = UIColor.redColor;
    [color set];
    UIBezierPath *bpath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height) cornerRadius:0];
    CGFloat rectWidth = kWidth * 3. / 4.;
    CGFloat rectHeight = rectWidth * 9. / 16.;
    CGPoint rectOrigin = CGPointMake(self.frame.size.width / 2. - rectWidth / 2., self.frame.size.height / 2. - rectHeight / 2.);
    [bpath appendPath:[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(rectOrigin.x - 10, rectOrigin.y - 50, rectWidth + 20 , rectHeight + 100) cornerRadius:0] bezierPathByReversingPath]];

    UIBezierPath *path = [UIBezierPath bezierPath];
    
    // Top left
    [path moveToPoint:CGPointMake(rectOrigin.x, rectOrigin.y + kLineLong)];
    [path addLineToPoint:CGPointMake(rectOrigin.x, rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectOrigin.x + kLineLong, rectOrigin.y)];
    path.lineWidth = kLineWidth;
    
    // Bottom left
    [path moveToPoint:CGPointMake(rectOrigin.x, rectHeight + rectOrigin.y - kLineLong)];
    [path addLineToPoint:CGPointMake(rectOrigin.x, rectHeight + rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectOrigin.x + kLineLong, rectHeight + rectOrigin.y)];
    path.lineWidth = kLineWidth;
    
    // Top right
    [path moveToPoint:CGPointMake(rectWidth + rectOrigin.x - kLineLong, rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectWidth + rectOrigin.x, rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectWidth + rectOrigin.x, rectOrigin.y + kLineLong)];
    path.lineWidth = kLineWidth;
    
    // Bottom right
    [path moveToPoint:CGPointMake(rectWidth + rectOrigin.x - kLineLong, rectHeight + rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectWidth + rectOrigin.x, rectHeight + rectOrigin.y)];
    [path addLineToPoint:CGPointMake(rectWidth + rectOrigin.x, rectHeight + rectOrigin.y - kLineLong)];
    path.lineWidth = kLineWidth;
    
    UIBezierPath *previewPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height) cornerRadius:0];
    [previewPath appendPath:[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(rectOrigin.x, rectOrigin.y, rectWidth, rectHeight) cornerRadius:0] bezierPathByReversingPath]];

    
    if (!self.isPreview) {
        [self addTextUI:@"Please put the card inside the brackets" pos:CGRectMake(rectOrigin.x, rectOrigin.y - 40, rectWidth, 20)];
        CAShapeLayer *shapeLayer = [CAShapeLayer layer];
        shapeLayer.path = bpath.CGPath;
        self.mView.layer.mask = shapeLayer;
        [path stroke];
    } else {
        CAShapeLayer *previewShapeLayer = [CAShapeLayer layer];
        previewShapeLayer.path = previewPath.CGPath;
        self.mView.layer.mask = previewShapeLayer;
        self.mView.alpha = 1.0;
    }
}
- (id)initWithFrame:(CGRect)frame isPreview: (BOOL)option {
    if (self = [super initWithFrame:frame]) {
        self.isPreview = option;
        self.backgroundColor = [UIColor clearColor];
        self.mView = [[UIView alloc] initWithFrame:self.bounds];
        self.mView.backgroundColor = [UIColor blackColor];
        self.mView.alpha = 0.8;
        [self addSubview:self.mView];
    }
    
    return self;
}

- (void)addTextUI:(NSString*)text pos:(CGRect)position {
    self.tipLabel = [[UILabel alloc] initWithFrame:position];
    self.tipLabel.text = text;
    self.tipLabel.textColor = UIColor.whiteColor;
    self.tipLabel.adjustsFontSizeToFitWidth = YES;
    [self addSubview:self.tipLabel];
}

@end
