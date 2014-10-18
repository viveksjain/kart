
/*

Copyright (c) 2012, 2013 RedBearLab

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

//"services.h/spi.h/boards.h" is needed in every new project
#include <SPI.h>
#include <boards.h>
#include <ble_shield.h>
#include <services.h>
#include <Servo.h>

#define MOTOR_LEFT         10
#define MOTOR_RIGHT        11

#define L_AC        4
#define L_AC2       5
#define L_AC_IN     A4

//The smaller the timer, the faster the car accelerates.
#define THROTTLETIMER 2
#define THROTTLE_MIN  1000
#define THROTTLE_MAX  2000

enum {
  THROTTLE = 0x1,
  STEER,
  DISCONNECT
};

uint8_t timer;
short rotation;     //init rotation at 0. - for Left, + for right.
int throttle;
Servo left;
Servo right;

void setup()
{
  // Default pins set to 9 and 8 for REQN and RDYN
  // Set your REQN and RDYN here before ble_begin() if you need
  //ble_set_pins(3, 2);

  // Set your BLE Shield name here, max. length 10
  //ble_set_name("My Shield");

  // Init. and start BLE library.
  ble_begin();

  // Enable serial debug
  Serial.begin(57600);
  pinMode(L_AC, OUTPUT);
  pinMode(L_AC2, OUTPUT);
  rotation = 0;
  throttle = THROTTLE_MIN;
  left.attach(MOTOR_LEFT);
  right.attach(MOTOR_RIGHT);

  // Default to internally pull high, change it if you need
  timer = 0;
}

short shortFromBytes(byte most_sig, byte least_sig) {
  short temp = most_sig;
  temp <<= 8;
  short temp2 = least_sig;
  return temp + temp2;
}

void loop()
{
  ble_do_events();
  timer = timer>=THROTTLETIMER?THROTTLETIMER:timer+1;

  if (!ble_connected()) {
    throttle = THROTTLE_MIN;
    process_throttle_and_rotation();
    return;
  }

  // If data is ready
  while(ble_available())
  {
    // read out command and data
    byte data0 = ble_read();
    byte data1 = ble_read();
    byte data2 = ble_read();

    if (data0 == THROTTLE) {
      Serial.print("Throttle: ");
      if(timer == THROTTLETIMER){
        int new_throttle = (int)shortFromBytes(data1, data2);
        if (new_throttle < THROTTLE_MIN) new_throttle = THROTTLE_MIN;
        if (new_throttle > THROTTLE_MAX) new_throttle = THROTTLE_MAX;
        throttle = new_throttle;
      }
      Serial.println(throttle);
    }
    else if (data0 == STEER) {
        Serial.print("Rotation: ");
        rotation = shortFromBytes(data1, data2);
        Serial.println(rotation);
    }
    else if (data0 == DISCONNECT) {
      Serial.println("Disconnect command received");
      throttle = THROTTLE_MIN;
    }
  }

  process_throttle_and_rotation();
}

//void decelerate() {
//  if(timer == THROTTLETIMER){
//    int new_throttle = throttle - decelerationSpeed;
//    if (new_throttle > throttle) throttle = THROTTLE_MIN;
//    else if (new_throttle < THROTTLE_MIN) throttle = THROTTLE_MIN;
//    else throttle = new_throttle;
//    timer = 0;
//  }
//}

void process_throttle_and_rotation() {
  left.writeMicroseconds(throttle);
  right.writeMicroseconds(throttle);

  //Write something for the Linear actuator pins. depending on the steering value.
  int potentiometer = analogRead(L_AC_IN);
  //Serial.println(potentiometer);
  if(rotation > potentiometer){
    digitalWrite(L_AC, HIGH);
    digitalWrite(L_AC2, LOW);
  }else{
    digitalWrite(L_AC2, HIGH);
    digitalWrite(L_AC, LOW);
  }
}
