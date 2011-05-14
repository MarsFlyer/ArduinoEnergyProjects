/* Gas Meter Logger - Transmitter on the Mini Arduino.

2011-03-26 Paul Allen

Uses a magnetic sensor (Hall effect) to detect the turning of the lowest digit on a gas meter.
This half of the program senses the gas meter changes and sends the data via an RF link.
Pseudo code:
 - Setup sensors
 - Loop every 30 seconds
 - Loop to detect magnetic changes
 - Send gas use over RF - for last 30 seconds, last 5 minutes and 5 minute periods.
Functions:

The circuit:
- Hall effect sensor (??), pin 2 with pull up resistor.
- RF Transmitter: pin 12 using VirtualWire as it is effective for RF. 
              not using software serial to allow debugging;
              but pin 0/1 for built in serial for full time use.

Completed enhancements:
- Keep totals for rolling last 5 minutes and previous 5 minute period.
- Sleep to save battery power.
- Awake on Interupt from Hall effect.
- Awake on timer to send data.

Didn't work:
- Turn RF power on only when needed - too inconsitent.

Future enhancements:
- None.
*/

// Libraries
#include <VirtualWire.h>   // For RF
#include <avr/sleep.h>     // For power modes
#include <avr/wdt.h>       // Watchdog Timer - available in all sleep modes.
#include <PinChangeInt.h>  // Pin change Interrupts.
#include <stdlib.h>        // Float to string

// Settings
///#define DEBUG 1
const long timeLoop = 30000;  // 30 seconds
const long timeLoops = 10;    // 5 minutes as 10 = 5 * 60/30
const int maxInterrupts = 4;  // 30 / 8 seconds = 4. Interrupts from pulses don't reduce the time!
const int magPin = 9;      // Magnetic sensor
const int ledPin = 13;     // Debug LED.
const int battPin = 0;     // Battery voltage.
const int rfPin = 3;       // Power to transmitter.
#define rxPin 6            // Serial (Software)
#define txPin 10            // Serial (Software)

// Common Definitions:
#ifdef DEBUG
  #define DEBUG_PRINT(x)      Serial.print (x)
  #define DEBUG_PRINTDEC(x)   Serial.print (x, DEC)
  #define DEBUG_PRINTLN(x)    Serial.println (x)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTDEC(x)
  #define DEBUG_PRINTLN(x)
#endif 

// Variables:
int magState = 0;         
int magLast = -1;
int battState = 0;
float battVal = 0;
int iWake = 0;
int iLoop = 0;
unsigned int iTime = 0;
unsigned int gasPulses = 0;
unsigned int gasThis = 0;
unsigned int gasPrev = 0;
unsigned int gasLast = 0;
unsigned int gasLoop[10];
unsigned long timeLast = 0;        // Milli seconds
unsigned long timeNow = 0;
String strPrep = "";
String strFull = "";
char *msg;

// Objects
PCintPort PCintPort();

void setup() {
  // Debugging only:
  #ifdef DEBUG
    Serial.begin(9600);          // start serial communication at 9600bps
    delay(3000);    // Wait for serial monitor to be setup
    Serial.println("Gas pulses");     
    Serial.println("Outer.Inner\tPulses\tLast10\tPrev");     
  #endif 

  // initialize pins as input / output:
  pinMode(ledPin, OUTPUT);     
  pinMode(magPin, INPUT);
  pinMode(battPin, INPUT);
  ///pinMode(rfPin, OUTPUT);     

  // VirtualWire for RF
  vw_set_tx_pin(txPin);
  vw_setup(2000); // Bits per sec  
  
  // Tx buffer seems to need initialising
  msg = "12345.1 5 999 999 3.0";
}

void loop(){
  // Every 5 minutes.
  iLoop = -1;
  iTime++;
  gasThis = 0;
  while (iLoop < timeLoops - 1) {
    iLoop += 1;
    timeLast = millis();
    timeNow = timeLast;
    gasPulses = 0;
    // For N minutes.
    while((timeNow - timeLast < timeLoop) && gasPulses < maxInterrupts) {
      iWake = 0;
      // Read magnetic
      sleepNow();
      magState = digitalRead(magPin);
      // Check for change. No need for de-bounce as the sensor latches.
      if (magState != magLast && magLast != -1) {
        if (magState == 1 && magLast != -1) {  
          gasPulses = gasPulses + 1;
          flashLed(200);
        } else {
          flashLed(100);
        }
      } 
      magLast = magState;
      timeNow = millis();
    }
    gasThis += gasPulses;
    gasLoop[iLoop] = gasPulses;
    gasLast = 0;
    for (int i=0; i <= 9; i++) {
      gasLast += gasLoop[i];
    }
    battState = analogRead(battPin);
    battVal = (float)battState * 3.3 / (float)1024;
    dtostrf(battVal, 5, 2, msg);

    strFull = iTime;
    strFull += ".";
    strFull += iLoop;
    strFull += "\t";
    strFull += gasPulses;
    strFull += "\t";
    strFull += gasLast;
    strFull += "\t";
    strFull += gasPrev;
    strFull += "\t";
    strFull += battState;
    strFull += "\t";
    strFull += msg;
    #ifdef DEBUG
      Serial.println(strFull);
    #endif
    int j = strFull.length() + 1;
    strFull.toCharArray(msg, j);
    //msg = "hello";
    //Serial.print(j);
    //Serial.println(strlen(msg));
    // This power approach didn't work:
    ///digitalWrite(rfPin, 1);   // turn on RF
    ///delay(500);  // wait for it to startup.
    vw_send((uint8_t *)msg, strlen(msg));
    vw_wait_tx(); // Wait until the whole message is gone
    ///digitalWrite(rfPin, 0);   // turn off RF
  }
  gasPrev = gasThis;
}

void flashLed (int i) {
  digitalWrite(ledPin, 1);
  delay(i);
  digitalWrite(ledPin, 0);
}

void wakeUpNow()        // here the interrupt is handled after wakeup
{
  // execute code here after wake-up before returning to the loop() function
  // timers and code using timers (serial.print and more...) will not work here.
  // we don't really need to execute any special functions here, since we
  // just want the thing to wake up
  iWake = 1;
}

void wakeUpTimer()        // here the interrupt is handled after wakeup
{
  // execute code here after wake-up before returning to the loop() function
  // timers and code using timers (serial.print and more...) will not work here.
  // we don't really need to execute any special functions here, since we
  // just want the thing to wake up
  iWake = 2;
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
  
  #ifdef DEBUG
    int pin2 = digitalRead(magPin);
  #endif

  // Don't sleep if it is already low.
  //if (sleepMode == 1 && pin2 == 0) {return;};

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
  else                   {return;};  // Don't bother sleeping

  #ifdef DEBUG
    if (sleepMode > 0) {
      // Time before sleep
      Serial.print("Sleep: ");
      Serial.print(pin2);
      Serial.print(" ");
      Serial.print(timeNow);
      Serial.print(" ");
      Serial.print(timeLast);
      Serial.print(" ");
      Serial.print(iDiff);
      Serial.print(" ");
      Serial.println(iWdt);
      delay(50);
    }
  #endif
  //timeLast -= iDiff;

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
      pin2 = digitalRead(magPin);
      // Time after sleep - Millis does not increment during power save!
      Serial.print("Wake : ");
      Serial.print(pin2);
      Serial.print(" ");
      Serial.print(millis());
      Serial.print(" ");
      Serial.print(timeLast);
      Serial.print(" ");
      Serial.println(millis() - timeLast);
    }
  #endif
  
  //flashLed(100);
  //delay(50);
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


