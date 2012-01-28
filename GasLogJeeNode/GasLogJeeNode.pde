/* Gas Meter Logger - Transmitter on the JeeNode.

2011-11-03 Paul Allen
2011-03-26 Paul Allen from GasLogMini

Uses a magnetic sensor (Hall effect) to detect the turning of the lowest digit on a gas meter.
This half of the program senses the gas meter changes and sends the data via an RF link.
Pseudo code:
 - Setup sensors & interupts
 - Watchdog timer every 8 seconds (max) or wake from interrupts.
    This allows the battery to last a long time.
 - Increment pulses when interupted
 - Send gas pulses (and battery voltage) over RF - approx every 30 seconds (if no interupts)
    or every n pulse(s) if interupts
Pseudo code for receiver:
 - Calculate the current power and overall energy use.
    This must be done at the receiver as the sleep code prevents good measurement of time on the transmitter.

Functions:

The circuit:
- Hall effect sensor, pin 2 with pull up resistor.
- RFM12 Transmitter using JeeLabs libraries. 

*/

#include "Config.h"      // Stores the RF node info.
//JeeLabs libraries
#include <Ports.h>
#include <RF12.h>
#include <avr/eeprom.h>
#include <util/crc16.h> //cyclic redundancy check
// Libraries
#include <avr/sleep.h>     // For power modes
#include <avr/wdt.h>       // Watchdog Timer - available in all sleep modes.
#include <PinChangeInt.h>  // Pin change Interrupts.

// Pins
const int magPin = 7;      // Magnetic sensor - Jeeode DIO4
const int ledPin = 9;     // Debug LED.
const int battPin = 3;     // Battery voltage - JeeNode AIO4 
const int battAio = 4;     // Battery voltage - JeeNode AIO4 

// TEST = High-level; DEBUG Low-level
#define TEST 1
#ifdef TEST
  #define TEST_PRINT(x)      Serial.print (x)
  #define TEST_PRINTDEC(x)   Serial.print (x, DEC)
  #define TEST_PRINTLN(x)    Serial.println (x)
#else
  #define TEST_PRINT(x)
  #define TEST_PRINTDEC(x)
  #define TEST_PRINTLN(x)
#endif 
///#define DEBUG 1
#ifdef DEBUG
  #define DEBUG_PRINT(x)      Serial.print (x)
  #define DEBUG_PRINTDEC(x)   Serial.print (x, DEC)
  #define DEBUG_PRINTLN(x)    Serial.println (x)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTDEC(x)
  #define DEBUG_PRINTLN(x)
#endif 

// Settings
const long timeLoop = 30000;  // 30 seconds
const int maxPulse = 3;       // Send before time if more than n Pulses 

// Variables:
int magState = 0;         
int magLast = -1;
int iWake = 0;
String sWake;
int iLoop = 0;
unsigned int gasPulses = 0;
unsigned int gasThis = 0;
unsigned long timeSent = 0;        // Last RF sent
unsigned long timeLast = 0;        // Sleep
unsigned long timeNow = 0;         // Sleep

// Objects
PCintPort PCintPort();

// RF Transmission
typedef struct { 
  int nPulse; // number of pulses recieved since last update
  int battV;  // battery voltage
} Payload;
Payload rftx;

void setup() {
  // Debugging only:
  #ifdef TEST
    Serial.begin(9600);    // Start serial communication at 9600bps
    flashLed(1500);        // Wait for serial monitor to be setup on PC
    Serial.println("Gas pulses");     
    Serial.println("Send\tPulses\tBattery V");     
  #endif 

  // initialize pins as input / output:
  pinMode(ledPin, OUTPUT);     
  pinMode(magPin, INPUT);
  pinMode(battPin, INPUT);
  
  delay(10);
  // RFM12B Initialize
  rf12_initialize(myNodeID,freq,network); //Initialize RFM12 with settings defined above
  
  delay(20);
  #ifdef TEST
    Serial.print("Node: ");
    Serial.print(myNodeID);
    Serial.print(" Freq: ");
     if (freq == RF12_433MHZ) Serial.print("433Mhz");
     if (freq == RF12_868MHZ) Serial.print("868Mhz");
     if (freq == RF12_915MHZ) Serial.print("915Mhz");
    Serial.print(" Network: ");
    Serial.println(network);
    delay(20);
  #endif 
  
  // Send on first loop.
  timeLast = millis() - timeLoop;
}

void loop(){
  #ifdef DEBUG
    DEBUG_PRINT("Loop:");
    DEBUG_PRINTLN(iLoop++);
    DEBUG_PRINT("Magnetic:");
    DEBUG_PRINTLN(digitalRead(magPin));
  #endif

  #ifdef DEBUG
      Serial.print("Now:");
      Serial.print(millis());
      Serial.print(" Last:");
      Serial.print(timeLast);
      Serial.print(" Diff:");
      Serial.println(millis() - timeLast);
  #endif 
  if (((millis() - timeLast) > timeLoop) || (gasThis >= maxPulse)) {
    rftx.battV = analogValue(battAio); //analogRead(battPin);
    ///battVal = (float)battState * 3.3 / (float)1024;
    ///dtostrf(battVal, 5, 2, msg);
    rftx.nPulse = gasPulses;
    
    #ifdef TEST
      Serial.print("Send:\t");     
      Serial.print(rftx.nPulse);    
      Serial.print("\t");     
      Serial.println(rftx.battV);    
    #endif 

    rfwrite();
    timeLast = millis();
    gasThis = 0;
  }
 
  #ifdef TEST
      delay(50);  // Allow serial to complete before sleeping.      
  #endif 

  sleepNow();
  // Read Hall sensor
  magState = digitalRead(magPin);
  // Check for change. No need for de-bounce as the sensor latches.
  if (magState != magLast && magLast != -1) {
    if (magState == 1 && magLast != -1) {  
      gasPulses++;
      gasThis++;
      flashLed(200);
      TEST_PRINT("On  ");
    } else {
      flashLed(100);
      TEST_PRINT("Off ");
    }
    TEST_PRINTLN(gasThis);
  } 
  magLast = magState;
  timeNow = millis();
}

// Send payload data via RF
static void rfwrite(){
    unsigned long timeStart = millis();
    TEST_PRINT("RF, time:");
    TEST_PRINT(timeStart);
    delay(50);
    TEST_PRINT(" diff:");
    TEST_PRINT(millis() - timeStart);
    rf12_sleep(-1); //wake up RF module
    rf12_recvDone();   // Need to do this otherwise canSend loops!
    while (!rf12_canSend()) {
      if ((millis() - timeStart) > 4000) {
        TEST_PRINTLN("RF failed.");
        rf12_sleep(0);
        return;
      }
    }
    rf12_recvDone();
    //rf12_hdr vs 0
    rf12_sendStart(0, &rftx, sizeof rftx); //, RADIO_SYNC_MODE);
    rf12_sendWait(0);  //Power-down mode during wait: 0 = NORMAL, 1 = IDLE, 2 = STANDBY, 3 = PWR_DOWN. Values 2 and 3 can cause the millisecond time to lose a few interrupts. Value 3 can only be used if the ATmega fuses have been set for fast startup, i.e. 258 CK - the default Arduino fuse settings are not suitable for full power down.
    rf12_sleep(0); //put RF module to sleep
    TEST_PRINTLN("RF sent.");
}

int analogValue(int aio) {
  int sensor = 0; 
  for (byte i = 0; i < 10; ++i) {
    sensor += analogRead(aio); 
  }
  sensor /= 10;
}

void flashLed (int i) {
  digitalWrite(ledPin, !1);
  delay(i);
  digitalWrite(ledPin, !0);
}

void wakeUpNow()        // here the interrupt is handled after wakeup
{
  // execute code here after wake-up before returning to the loop() function
  // timers and code using timers (serial.print and more...) will not work here.
  // we don't really need to execute any special functions here, since we
  // just want the thing to wake up
  sWake = "Int ";
}

void sleepNow() {
  /* Now is the time to set the sleep mode. In the Atmega8 datasheet
   * http://www.atmel.com/dyn/resources/prod_documents/doc2486.pdf on page 35
   * there is a list of sleep modes which explains which clocks and 
   * wake up sources are available in which sleep mode.
   *
   * In the avr/sleep.h file, the call names of these sleep modes are to be found:
   *     SLEEP_MODE_IDLE         -the least power savings 
   *     SLEEP_MODE_ADC
   *     SLEEP_MODE_PWR_SAVE     -Timer2 is available
   *     SLEEP_MODE_STANDBY
   *     SLEEP_MODE_PWR_DOWN     -the most power savings
  */
  /* Now it is time to enable an interrupt. We do it here so an 
  * accidentally pushed interrupt button doesn't interrupt 
  * our running program. if you want to be able to run 
  * interrupt code besides the sleep function, place it in 
  * setup() for example.
  * 
  * In the function call attachInterrupt(A, B, C)
  * A   can be either 0 or 1 for interrupts on pin 2 or 3.   
  * 
  * B   Name of a function you want to execute at interrupt for A.
  *
  * C   Trigger mode of the interrupt pin. can be:
  *             LOW        a low level triggers
  *             CHANGE     a change in level triggers
  *             RISING     a rising edge of a level triggers
  *             FALLING    a falling edge of a level triggers
  *         in all but the IDLE sleep modes only LOW can be used.
  */
  /*
  The pin change interrupt PCI2 will trigger if any enabled PCINT[23:16] pin toggles. The pin change
interrupt PCI1 will trigger if any enabled PCINT[14:8] pin toggles. The pin change interrupt PCI0
will trigger if any enabled PCINT[7:0] pin toggles.
  */

  int sleepMode = 1;    // Mode 2 not needed after using pin change library.
  
  unsigned int iDiff =  timeLoop - (timeNow - timeLast);

  // 0=16ms, 1=32ms,2=64ms,3=128ms,4=250ms,5=500ms
  // 6=1 sec,7=2 sec, 8=4 sec, 9= 8sec
  int iWdt = 0;
  if (iDiff > 8000)      {iWdt = 9; iWake = 8000;}
  else if (iDiff > 4000) {iWdt = 8; iWake = 4000;}
  else if (iDiff > 2000) {iWdt = 7; iWake = 2000;}
  else if (iDiff > 1000) {iWdt = 6; iWake = 1000;}
  else if (iDiff > 500)  {iWdt = 5; iWake = 500;}
  // Sleep for a shorter time otherwise pulses can prevent the timer from finishing.
  ///if (iDiff > 2000)      {iWdt = 6; iWake = 2000;}
  else if (iDiff > 0)  {iWdt = 5; iWake = 500;}  // Always sleep at least 0.5 seconds.
  else                   {return;};  // Don't bother sleeping

  #ifdef DEBUG
    if (sleepMode > 0) {
      // Time before sleep
      Serial.print("Sleep, Value: ");
      Serial.print(digitalRead(magPin));
      Serial.print(" Now:");
      Serial.print(timeNow);
      Serial.print(" Prev:");
      Serial.print(timeLast);
      Serial.print(" Diff:");
      Serial.print(iDiff);
      Serial.print(" WDT:");
      Serial.println(iWdt);
      delay(50);  // Allow serial to complete before sleeping.
    }
  #endif

  sWake = "Wake";

  if (sleepMode == 1) {
    // Pin Change & Watchdog timer both work in lowest power down mode!
    ///set_sleep_mode(SLEEP_MODE_PWR_SAVE);
    set_sleep_mode(SLEEP_MODE_PWR_DOWN);
    setup_watchdog(iWdt);
    sleep_enable();
    // Interrupt runs function wakeUpNow..
    PCintPort::attachInterrupt(magPin, wakeUpNow, CHANGE);
  }
  if (sleepMode == 2) {
    set_sleep_mode(SLEEP_MODE_IDLE);
    setup_watchdog(iWdt);
    sleep_enable();
    ///attachInterrupt(0,wakeUpNow, CHANGE);
  }

  sleep_mode();            // here the device is actually put to sleep!!
                           // THE PROGRAM CONTINUES FROM HERE AFTER WAKING UP

  sleep_disable();         // first thing after waking from sleep:
                           // disable sleep...
  ///detachInterrupt(0);      // disables interrupt 0 on pin 2 so the 
                           // wakeUpNow code will not be executed 
                           // during normal running time.
  PCintPort::PCdetachInterrupt(magPin);

  #ifdef DEBUG
    if (sleepMode > 0) {
      Serial.print(sWake);
      Serial.print(", Value: ");
      Serial.print(digitalRead(magPin));
      Serial.print(" Now:");
      Serial.print(timeNow);
      Serial.print(" Prev:");
      Serial.print(timeLast);
      Serial.print(" Diff:");
      Serial.print(iDiff);
      Serial.print(" WDT:");
      Serial.println(iWdt);
    }
  #endif
}

// 0=16ms, 1=32ms,2=64ms,3=128ms,4=250ms,5=500ms
// 6=1 sec,7=2 sec, 8=4 sec, 9= 8sec
void setup_watchdog(int ii) {

  byte bb;
  int ww;
  if (ii > 9 ) ii=9;
  bb=ii & 7;
  if (ii > 7) bb|= (1<<5);
  bb|= (1<<WDCE);
  ww=bb;
  ///Serial.println(ww);

  MCUSR &= ~(1<<WDRF);
  // start timed sequence
  WDTCSR |= (1<<WDCE) | (1<<WDE);
  // set new watchdog timeout value
  WDTCSR = bb;
  WDTCSR |= _BV(WDIE);
}

// Watchdog Interrupt Service / is executed when  watchdog timed out
ISR(WDT_vect) {
  timeLast -= iWake;  //adjust for missing Millis.
}

