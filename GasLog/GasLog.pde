/* Gas Meter Logger

2011-03-04 Paul Allen

Uses a magnetic sensor (Hall effect) to detect the turning of the lowest digit on a gas meter.
Pseudo code:
- Setup sensors
- Loop every 5 minutes
 - Loop to detect magnetic changes
 - Write time, gas use and temperature to SD card
Functions:
- dataWrite
- temperatureGet

The circuit:
- Hall effect sensor (??), pin 2 with pull up resistor.
- I2C temperature sensor (Lego ??), A4 = SDA? = Lego 6; A5 = SCL? = Lego 5; +5V = Lego 4; 0V = Lego 3.
- SD card on Ethernet Shield, to store results

Enhancements complete:
- Sync time using HTTP response (requires continuous power afterwards)

Enhancements to improve:
- Memory problems, so need to reduce use of strings, libraries etc.
- LED display, only in non-debug mode to save on memory.
- Ethernet to pachube
- Sync time month decode (PROGMEM for array?)

Future enhancements:
- Display Watt usage ("instant" & cummulative)
- RF Receiver

Enhancements complete on Mini-Pro:
- RF Transmitter on Arduino Pro-mini running at 3.3V
- Sleep on Pro-mini to save battery power
- Interupt from Hall effect for deeper sleep

Rejected features:
- NTP time sync: not reliable over firewalls. Use HTTP response time instead.
*/

// For detailed debuging:
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

// For main testing:
#define TESTING 1
#ifdef TESTING
  #define TEST_PRINT(x)      Serial.print (x)
  #define TEST_PRINTDEC(x)   Serial.print (x, DEC)
  #define TEST_PRINTLN(x)    Serial.println (x)
#else
  #define TEST_PRINT(x)
  #define TEST_PRINTDEC(x)
  #define TEST_PRINTLN(x)
#endif 

#define LED_ON 1 
//#define SD_ON 1 

#include <avr/io.h>
#include <avr/wdt.h>       // Watchdog Timer
#include <Wire.h>          // For I2C/SPI Temperature sensor
///#include <SD.h>            // For SD Card on Ethernet Shield
#include <Ethernet.h>      // For sending to pachube
#include <SPI.h>           // needed by Ethernet.h
#ifdef LED_ON
  #include <NewSoftSerial.h> // For LED display
#endif
#include <Time.h>          // For time sync
#include <avr/pgmspace.h>  // To store http literal strings
#include <MemoryFree.h>    // To check memory problems.
#include <VirtualWire.h>   // For RF Receiver.

// Ethernet settings
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x34, 0xF2 };  
#define ROUTER 1
#define WIN7 1
#ifdef ROUTER
  byte ip[] = { 192, 168, 1, 21 };    // via router
  byte gateway[] = { 192, 168, 1, 1 };
  byte subnet[]  = { 255, 255, 255, 0 };
#else
  #ifdef WIN7
    byte ip[] = { 192, 168, 137, 21 };    // via XPS
    byte gateway[] = { 192, 168, 137, 1 };
    byte subnet[]  = { 255, 255, 255, 0 };
  #else
    byte ip[] = { 192, 168, 0, 21 };    // via XPS
    byte gateway[] = { 192, 168, 0, 1 };
    byte subnet[]  = { 255, 255, 255, 0 };
  #endif     
#endif 

// pachube settings
byte server[] = { 173, 203, 98, 29 }; // api.pachube.com
//#define PACHUBE_API_KEY   "XXX" // fill in your API key 
//#define PACHUBE_FEED_ID    19886    // this is the ID of the remote Pachube feed that you want to connect to

// Inputs & Outputs
#define magPin 2       // Magnetic sensor
#define addrTemperature1 76   // Temperature sensor
#define ledPin 7      // Debug LED.
#define rxPin 5    // not used
#define txPin 6    // LED display
#define rfPin 8    // RF receiver
#define resetPin 9    // Ethernet reset
// A4 I2C SDA (Lego Red -2)
// A5 I2C SCL (Lego Red -3)

// contstants:
//#define timeLoop 30000  // 30 seconds - too frequently requires a logon.
#define timeLoop 60000  // 60 seconds
//#define timeLoop 300000  // 5 minutes = 300 seconds


// Ethernet Board: communicates with both the W5100 and SD card using the SPI bus (through the ICSP header).
// This is on digital pins 11, 12, and 13 
// pin 10 is used to select the W5100
// and pin 4 for the SD card. These pins cannot be used for general i/o.

// Objects:
#ifdef LED_ON
  NewSoftSerial displaySerial(rxPin, txPin);
#endif
Client client(server, 80);

// variables: (unneeded initialising uses memory!)
/* Initialise within code
int magState = 0;         
int magLast = -1;
int iLoop = 0;
int iLoop2; // = 0;
float temperature1; // = 0;
long gasPulses; // = 0;
unsigned long timeLast; // = 0;        // Milli seconds
unsigned long timeNow; // = 0;
String strFull;
char * filename;
*/
///File logfile;
char buf[80];
char buf2[40];
char battBuf[5];
char ledBuf[5];
char cDate[20];

long previousWdtMillis = 0;
long wdtInterval = 0;

///const char httpTest[] PROGMEM = "\r\nContent-Type: application/x-www-form-urlencoded/r/n/r/n";

void setup() {
  MCUSR=0;
  wdt_enable(WDTO_8S); // setup Watch Dog Timer to 8 sec

  #ifdef TESTING
    // Debugging only:
    Serial.begin(9600);          // start serial communication at 9600bps
    pinMode(ledPin, OUTPUT);     
    delay(2000);    // Wait for serial monitor to be setup
    Serial.println("GasLog");
    
    ///Serial.println(getString(httpTest));
  #endif
  TEST_PRINTLN(freeMemory());

  // initialize pins as input / output:
  pinMode(magPin, INPUT);   
  pinMode(ledPin, OUTPUT);   
  pinMode(rxPin, INPUT);   
  pinMode(txPin, OUTPUT);   
/*  digitalWrite(resetPin, true);
  pinMode(resetPin, OUTPUT);   
  digitalWrite(resetPin, true);
*/
  // join I2C bus (address optional for master)
  ///Serial.println("Setup I2C");
  Wire.begin();
  temperatureSetup(addrTemperature1);
  
  // SD Card
  #ifdef SD_ON
    DEBUG_PRINTLN("Setup SD");
    filename = "gas2.log";
    SD.begin();
    logfile = SD.open(filename, FILE_WRITE);
  #endif

  // LED Display
  #ifdef LED_ON
    DEBUG_PRINTLN("Setup LED");
    displaySerial.begin(9600);
    displaySerial.print("z");  // Reduce brightness
    displaySerial.print(0x80);  
    delay(100);
    displaySerial.print("w");  // Reduce brightness
    displaySerial.print(B00000000,BYTE);  // 00, Apos, Colon, 1234., 123.4, 12.34, 1.234 
    delay(100);
    displaySerial.print("v\0");  // Clear
    displaySerial.print("----\0");
  #endif

  // Ethernet
  ///Serial.println("Setup Ethernet");
/*  Ethernet.begin(mac, ip);
  delay(250);
  DEBUG_PRINTLN(freeMemory());  */
  ethernetInit();
  
  ///Serial.println("Gas\tTemperature");

  // Initialise the IO and ISR
  ///vw_set_ptt_inverted(true); // Required for DR3100
  vw_set_rx_pin(rfPin);
  vw_setup(2000);      // Bits per sec
  vw_rx_start();       // Start the receiver PLL running
}

int temperature1;
int iNum;
int iDec;
int gasPulses = 0;
int iConnections = 0;
int iLoop = 0;

void loop(){
  // For ever
  int magLast = -1;
  unsigned long lastRF = 0;
  while (1==1) {
    iLoop++;
    TEST_PRINTLN(datetimeString(now()));
    TEST_PRINT(freeMemory());
    TEST_PRINT(" Loop:");
    TEST_PRINTLN(iLoop);
    
    // Test Ethernet reset by using watchdog reset every n loops.
    if (1==0 && iLoop > 2) {
      TEST_PRINTLN("Watchdog restart.");
      delay(10000); // Greater than 8 seconds.
    }
    
    // Send to pachube
    DEBUG_PRINT(freeMemory());
    DEBUG_PRINTLN(" pachube");
    // 0=Gas 1=Temperature 2=Battery 3=Resets
    sprintf(buf,"0,%d\r\n1,%d.%d\r\n2,%s\r\n3,%d\0", gasPulses, iNum, iDec, battBuf, iConnections); 
    DEBUG_PRINTLN(buf);
    wdt_reset();
    pachube("PUT", buf);

    displayLED();

    #ifdef SD_ON
      DEBUG_PRINT(freeMemory());
      DEBUG_PRINTLN(" file");
      sprintf(buf,"%s\t%d\t%d.%d\0", datetimeString(now()), gasPulses, iNum, iDec); 
      DEBUG_PRINTLN(buf);
      // Save to SD Card
      DEBUG_PRINTLN(" SD Save");
      logfile.println(buf);
      logfile.flush();
    #endif

    DEBUG_PRINT(freeMemory());
    DEBUG_PRINTLN(" Wait:");
    ///DEBUG_PRINTLN(timeLast);
    long timeLast = millis();
    int iLoop2 = 0;
    // For N minutes.
    while(millis() - timeLast < timeLoop) {
      iLoop2 += 1;
      
      // Watch Dog Timer will reset the arduino if it doesn't get "wdt_reset();" every 8 sec
      if ((millis() - previousWdtMillis) > wdtInterval) {
        previousWdtMillis = millis();
        wdtInterval = 5000;
        wdt_reset();
       /// Serial.println("wdt reset");
      }

      uint8_t buf[VW_MAX_MESSAGE_LEN];
      uint8_t buflen = VW_MAX_MESSAGE_LEN;
  
      if (vw_get_message(buf, &buflen)) // Non-blocking
      {
        digitalWrite(ledPin, true); // Flash a light to show received good message
        lastRF = millis();
  	// Message with a good checksum received, dump it.
  	TEST_PRINT("Got: ");
  	
        // Message format from MiniPro: Outer.Inner\tPulses\tLast10\tPrev\tbattVal\tBattVolts
  	int i;
        int j = 0;
        int t = 0;
        char c;
  	for (i = 0; i < buflen; i++)
  	{
          c = buf[i];
  	  TEST_PRINT(buf[i]);
          if (c=='\t') {t++;}
          else {
            if (t==2) {battBuf[j] = c; j++;}  //
            if (t==5) {j++; if (j>=0) {battBuf[j] = c;};}  //delete leading space 
            if (t==3) {
              battBuf[j] = '\0';
              gasPulses = atoi(battBuf);
              ///DEBUG_PRINT("pulses:");
              ///DEBUG_PRINTLN(battBuf);
              j = -2;
            }
          }
  	}
        j++;
        battBuf[j] = '\0';
        TEST_PRINTLN("");
        DEBUG_PRINT(datetimeString(now()));
        DEBUG_PRINT(" Extract:");
        DEBUG_PRINT(battBuf);
        DEBUG_PRINT(";");
        DEBUG_PRINTLN(gasPulses);
        displayLED();
      }
      if ((lastRF != 0) && (millis() - lastRF > 70000)) {  // Should be every 30 seconds therefore 70 seconds 
        DEBUG_PRINT(datetimeString(now()));
        DEBUG_PRINTLN(" RF off.");
        gasPulses = 0;
        battBuf[0] = '\0';
        digitalWrite(ledPin, false);
        lastRF = 0;
      }
    }
  }
}

void displayLED() {
  getTemperature();
  // Calculate gas kWh 1 pulse = 111 Wh
  ///float fGas = gasPulses * 111

  #ifdef LED_ON
    DEBUG_PRINT(freeMemory());
    DEBUG_PRINT(" LED:");
    // Display on LED
    sprintf(ledBuf, "%2d%2d\0", iNum, gasPulses); 
    sprintf(ledBuf, "%4d\0", iConnections); 
    DEBUG_PRINTLN(ledBuf);
    displaySerial.print("v\0");    // Clear contents
    displaySerial.print(ledBuf);
  #endif  
}

void getTemperature() {
  // Read temperature
  temperature1 = temperatureRead(addrTemperature1);
  iNum = (temperature1/10);
  iDec = (temperature1 - (iNum)*10) ;
}


// Display functions:
char* datetimeString(unsigned long t){
  sprintf(cDate,"%4d-%02d-%02dT%02d:%02d:%02d\0", year(t), month(t), day(t), hour(t), minute(t), second(t)); 
  return cDate;
}

