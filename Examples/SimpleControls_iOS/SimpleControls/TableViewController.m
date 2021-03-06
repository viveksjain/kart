//
//  TableViewController.m
//  SimpleControl
//
//  Created by Cheong on 7/11/12.
//  Copyright (c) 2012 RedBearLab. All rights reserved.
//

#import "TableViewController.h"

@interface TableViewController ()

@end

@implementation TableViewController

@synthesize ble;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    ble = [[BLE alloc] init];
    [ble controlSetup];
    ble.delegate = self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (CMMotionManager *)motionManager
{
    if(!motionManager) {
        motionManager = [[CMMotionManager alloc] init];
        motionManager.accelerometerUpdateInterval = 1;
    }
    return motionManager;
}

#pragma mark - BLE delegate

NSTimer *rssiTimer;

- (void)bleDidDisconnect
{
    NSLog(@"->Disconnected");

    [btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
    [indConnecting stopAnimating];
    
    lblAnalogIn.enabled = false;
    swDigitalOut.enabled = false;
    swDigitalIn.enabled = false;
    swAnalogIn.enabled = false;
    sldPWM.enabled = false;
    sldServo.enabled = false;
    
    lblRSSI.text = @"---";
 //   lblAnalogIn.text = @"----";
    
    [rssiTimer invalidate];
}

// When RSSI is changed, this will be called
-(void) bleDidUpdateRSSI:(NSNumber *) rssi
{
    lblRSSI.text = rssi.stringValue;
}

-(void) readRSSITimer:(NSTimer *)timer
{
    [ble readRSSI];
}

// When disconnected, this will be called
-(void) bleDidConnect
{
    NSLog(@"->Connected");

    [indConnecting stopAnimating];
    
    lblAnalogIn.enabled = true;
    swDigitalOut.enabled = true;
    swDigitalIn.enabled = true;
    swAnalogIn.enabled = true;
    sldPWM.enabled = true;
    sldServo.enabled = true;
    
    swDigitalOut.on = false;
    swDigitalIn.on = false;
    swAnalogIn.on = false;
    sldPWM.value = 0;
    sldServo.value = 0;
    
    // send reset
    UInt8 buf[] = {0x04, 0x00, 0x00};
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];

    // Schedule to read RSSI every 1 sec.
    rssiTimer = [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(readRSSITimer:) userInfo:nil repeats:YES];
    
    [[self motionManager] startDeviceMotionUpdates];
    
    while (true) {
        double pitch = [self motionManager].deviceMotion.attitude.pitch;
        int value = pitch * 512 + 512;
        value = MAX(0, value);
        value = MIN(1023, value);
        NSLog(@"%d", value);
        [self sendLActuator:value];
        [NSThread sleepForTimeInterval:.2];
    }
}

// When data is comming, this will be called
-(void) bleDidReceiveData:(unsigned char *)data length:(int)length
{
    NSLog(@"Length: %d", length);

    // parse data, all commands are in 3-byte
    for (int i = 0; i < length; i+=3)
    {
        NSLog(@"0x%02X, 0x%02X, 0x%02X", data[i], data[i+1], data[i+2]);

        if (data[i] == 0x0A)
        {
            if (data[i+1] == 0x01)
                swDigitalIn.on = true;
            else
                swDigitalIn.on = false;
        }
        else if (data[i] == 0x0B)
        {
            UInt16 Value;
            
            Value = data[i+2] | data[i+1] << 8;
            lblAnalogIn.text = [NSString stringWithFormat:@"%d", Value];
        }        
    }
}

-(void) testingAccelerometerData
{
    NSTimeInterval interval = .1; // 100ms
    [[self motionManager] setDeviceMotionUpdateInterval:interval];
    
    [[self motionManager] startDeviceMotionUpdatesToQueue:[[NSOperationQueue alloc] init] withHandler:^(CMDeviceMotion *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            double pitch = data.attitude.pitch;
            int value = pitch * 512 + 512;
            value = MAX(0, value);
            value = MIN(1023, value);
            NSLog(@"%d", value);
        });
    }];
}

#pragma mark - Actions

// Connect button will call to this
- (IBAction)btnScanForPeripherals:(id)sender
{
    // FOR PLAYING AROUND:
    [self testingAccelerometerData];
    
    if (ble.activePeripheral)
        if(ble.activePeripheral.state == CBPeripheralStateConnected)
        {
            [[ble CM] cancelPeripheralConnection:[ble activePeripheral]];
            [btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
            return;
        }
    
    if (ble.peripherals)
        ble.peripherals = nil;
    
    [btnConnect setEnabled:false];
    [ble findBLEPeripherals:2];
    
    [NSTimer scheduledTimerWithTimeInterval:(float)2.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
    
    [indConnecting startAnimating];
}

-(void) connectionTimer:(NSTimer *)timer
{
    [btnConnect setEnabled:true];
    [btnConnect setTitle:@"Disconnect" forState:UIControlStateNormal];
    
    if (ble.peripherals.count > 0)
    {
        [ble connectPeripheral:[ble.peripherals objectAtIndex:0]];
    }
    else
    {
        [btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
        [indConnecting stopAnimating];
    }
}

-(IBAction)sendDigitalOut:(id)sender
{
    UInt8 buf[3] = {0x01, 0x00, 0x00};
    
    if (swDigitalOut.on)
        buf[1] = 0x01;
    else
        buf[1] = 0x00;
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

/* Send command to Arduino to enable analog reading */
-(IBAction)sendAnalogIn:(id)sender
{
    UInt8 buf[3] = {0xA0, 0x00, 0x00};
    
    if (swAnalogIn.on)
        buf[1] = 0x01;
    else
        buf[1] = 0x00;
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

-(void)sendLActuator:(int)value
{
    UInt8 buf[3] = {0x03, 0x00, 0x00};
    
    buf[2] = value;
    buf[1] = value >> 8;
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

// PWM slide will call this to send its value to Arduino
-(IBAction)sendPWM:(id)sender
{
    [self sendLActuator:sldPWM.value];
}

// Servo slider will call this to send its value to Arduino
-(IBAction)sendServo:(id)sender
{
    UInt8 buf[3] = {0x03, 0x00, 0x00};
    
    buf[2] = sldServo.value;
    buf[1] = (int)sldServo.value >> 8;
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

@end
