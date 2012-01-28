/* Changed to handle Gas Pulses.
   by Paul Allen 
   Updated 2011-11-17
   
   The pulse transmitting node is optimised for low battery use, so all it does is...
   1. Respond to interupts from the magnetic sensor
   2. Count the total nmber of pulses since it was started.
      (use unsigned int?)
   3. Send the results and battery voltage,
     3a. every 32 seconds (4 * 8 second watchdog timers 
     3b. every 3 full pulses (low & high)
    
   Calculations are done on the receiving node:
   (to handle calculations use signed long?)
   1. kW = (pulses2 - pulses1) / 100 * factor * 3600 / (seconds2 - seconds1)
     1a. Factor = kWh/m3 as per your gas bill e.g. 11.13
     1b. Readings sent every 32seconds or less, so average to 1 minute, by shifting previous results.
   2. Total kWh for the day
     2a. When the date changes (taken from the Pachube response), store the current pulse count.
           set start = current
           set previous day's kWh
           store to EEPROM
     2b. Handle restarts of the transmitter
         If (latest < previous) and (latest < 100)
           subtract previous from start
           store to EEPROM
           set recent results to 0  
           (e.g. don't calculate the kW, it is probably due to a battery change when nothing is happening anyway).
     2c. Handle restarts of the receiver
           get start from EEPROM
     2d. Handle round the clock of the transmitter 
         If ((latest < previous) and (previous - latest > 32000)) 
   3. kWh diff for previous 24 hours
     3a. When the hour changes (taken from the Pachube response), store the current pulse count.
           set this hour = current
           store to EEPROM
   9. Display values on the 4 digit LED display
     9a. Current kW: "k12.3"
     9b. Day kWh: "d12.3"
     9c. Diff from previous day: "+12.3" "-12.3"
/*                          _                                                      _      
                           | |                                                    | |     
  ___ _ __ ___   ___  _ __ | |__   __ _ ___  ___       _ __   __ _ _ __   ___   __| | ___ 
 / _ \ '_ ` _ \ / _ \| '_ \| '_ \ / _` / __|/ _ \     | '_ \ / _` | '_ \ / _ \ / _` |/ _ \
|  __/ | | | | | (_) | | | | |_) | (_| \__ \  __/  _  | | | | (_| | | | | (_) | (_| |  __/
 \___|_| |_| |_|\___/|_| |_|_.__/ \__,_|___/\___| (_) |_| |_|\__,_|_| |_|\___/ \__,_|\___|
                                                                                          
*/
//--------------------------------------------------------------------------------------
// Relay's data recieved by emontx up to pachube
// Minimal CT and supply voltage only version

// Uses JeeLabs RF12 library http://jeelabs.org/2009/02/10/rfm12b-library-for-arduino/
// Uses Andrew Lindsay's EtherShield library - using DHCP

// By Glyn Hudson and Trystan Lea
// openenergymonitor.org
// GNU GPL V3

// Last update: 12th of November 2011
//--------------------------------------------------------------------------------------
#define DEBUG
#define LEDLOW            // Used by status LED
#define RF
#define ONEWIRE 1
#define USELEDSEG         // 7 SEgment LED display

//---------------------------------------------------------------------
// RF12 link - JeeLabs
//---------------------------------------------------------------------
#include <Ports.h>
#include <RF12.h>
//---------------------------------------------------------------------
// Ethernet - Andrew Lindsay
//---------------------------------------------------------------------
#include <EtherShield.h>
#include <EEPROM.h>
#include <Time.h>          // For time sync
#include "Config.h"
#include <MemoryFree.h>    // To check memory problems.

#ifdef USELEDSEG
  #include <NewSoftSerial.h>
  NewSoftSerial LEDSEG(4, 5);    // For 7 Segment LED display rx (not used), tx (used) 
#endif 

// For one-wire:
#ifdef ONEWIRE
  #include <OneWire.h>            // Internal temperature.
  #include <DallasTemperature.h>
  #define pinOneWire 7  // One-wire bus
  // Objects:
  // Setup a oneWire instance to communicate with any OneWire devices (not just Maxim/Dallas temperature ICs)
  OneWire oneWire(pinOneWire);
  // Pass our oneWire reference to Dallas Temperature. 
  DallasTemperature sensors(&oneWire);
#endif

#ifdef DEBUG
  #define DEBUG_PRINT(x)      Serial.print (x)
  #define DEBUG_PRINTDEC(x)   Serial.print (x, DEC)
  #define DEBUG_PRINTLN(x)    Serial.println (x)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTDEC(x)
  #define DEBUG_PRINTLN(x)
#endif 

// The RF12 data payload - a neat way of packaging data when sending via RF - JeeLabs
typedef struct
{
  int pulse;		    // current transformer 1
  int supplyV;              // emontx voltage
} Payload;
Payload emontx;              
// RF Transmission
/*typedef struct { 
  int nPulse; // number of pulses recieved since last update
  int battV;  // battery voltage
} Payload;
Payload rftx; */

//---------------------------------------------------------------------
// The PacketBuffer class is used to generate the json string that is send via ethernet - JeeLabs
//---------------------------------------------------------------------
class PacketBuffer : public Print {
public:
    PacketBuffer () : fill (0) {}
    const char* buffer() { return buf; }
    byte length() { return fill; }
    void reset()
    { 
      memset(buf,NULL,sizeof(buf));
      fill = 0; 
    }
    virtual void write(uint8_t ch)
        { if (fill < sizeof buf) buf[fill++] = ch; }
    byte fill;
    char buf[70];
    private:
};
PacketBuffer str;

// Ethernet config:
byte mac[6] =     { 0x04,0x13,0x31,0x13,0x05,0x22};           // Unique mac address - must be unique on your local network
byte server[4] = {173,203,98,29};    // Pachube IP, should use DNS!

//---------------------------------------------------------------------

// Flow control varaiables
int dataReady=0;                                                  // is set to 1 when there is data ready to be sent
unsigned long milRF;                                             // used to check for RF recieve failures
int post_count;                                                   // used to count number of ethernet posts that dont recieve a reply

int pulsePrev=0;           // Counters
long pulseStart=0;
int pulseHour[24];         // Holds the pulse count at the start of each hour
int timeHour[24];          // Holds the time in quarter days (since the start of 2012)
unsigned long time2012;     // The start of the year in hours, using Unix time
unsigned long timePrev;    // Last times
tmElements_t tm;
int iDay=0;
int iHour=-1;
int iTest = 0;             // For testing a steady rate. 
//iTest = 2;

// Timing globals:
unsigned long milPachube;
#define milPachubeInterval 25000L  // Don't send data more frequently. 25 sec
unsigned long milNext;
#define milMinInterval 60000L  // Send indoor temperature if no gas daat. 60 sec
unsigned long milDisplay;
#define milDisplayInterval 20000L  // Rotating LED segment display. 20 sec
int iDisplay;  // What to show.

// Watts config:
float gasKWHM3 = 11.13;   // From gas bill 

// Data globals
float fTemperature;
float kW;
float kWhDay;
float kWh24;
char ledBuf[5];
char fString[10];

//---------------------------------------------------------------------
// Setup
//---------------------------------------------------------------------
void setup()
{
  Serial.begin(9600);
  Serial.println("GasLogNanode");
  Serial.print("Node: "); Serial.print(MYNODE); 
  ///Serial.print(" Freq: "); Serial.print("433Mhz"); 
  Serial.print(" Group: "); Serial.println(group);
  ///Serial.print("Posting to "); printIP(server); Serial.print(" "); Serial.println(PACHUBE_VHOST);
  
  ethernet_setup_dhcp(mac,server,80,8); // Last two: PORT and SPI PIN: 8 for Nanode, 10 for nuelectronics
  
  #ifdef RF
  rf12_initialize(MYNODE, freq,group);
  #endif

  pinMode(6, OUTPUT);
  ledStatus(true); delay(1000); ledStatus(false);                // Nanode indicator LED setup, HIGH means off! if LED lights up indicates that Etherent and RFM12 has been initialize
  
  #ifdef USELEDSEG
    LEDSEG.begin(9600);
    LEDSEG.print("z");  // Full brightness
    LEDSEG.print("v\0");  // Clear contents
    LEDSEG.print("----\0");
  #endif

  #ifdef ONEWIRE
    sensors.begin();  // Enable One Wire.
  #endif
  
  // Read initial counters
  pulseStart = EEPROMReadInt(24*2);
  iDay = EEPROMReadInt(25*2);
  DEBUG_PRINTLN("EEPROM data:");
  for(int h = 0; h<24; h++)
  {
    unsigned int val;
    pulseHour[h] = EEPROMReadInt(h*2);
    timeHour[h] = EEPROMReadInt((h+26)*2);  
    DEBUG_PRINT(h);
    DEBUG_PRINT(" ");
    DEBUG_PRINT(pulseHour[h]);
    DEBUG_PRINT(" ");
    DEBUG_PRINTLN(timeHour[h]);
  }
  if (false) {
    // For intraday testing
    setTime(8,0,0,28,1,2012);  //hr,min,sec,day,month,yr);
    DEBUG_PRINTLN(timeDiff(now()));
  }
  if (true) {
    // For intraday testing
    for(int h = 0; h<24; h++)
    {
      ///if (timeHour[h] < 100) {timeHour[h] = 5558;}
      timeHour[h] = 120;
      if (pulseHour[h] < 6000) {pulseHour[h] = 6000;}
    }
  }
  // To setup EEPROM
  if (false) {
    pulseStart = 4000;
    EEPROMWriteInt(24*2,pulseStart);
    iDay = 29;
    EEPROMWriteInt(25*2,iDay);
  }
  milPachube = millis() - milPachubeInterval; // Use first loop.
  milNext = millis() + 20000L;   // Give 20 seconds to do DHCP.
  milDisplay = millis();
  milRF = millis();
  
  DEBUG_PRINT("Mem=");
  DEBUG_PRINTLN(freeMemory());
}

//-----------------------------------------------------------------------
// Loop
//-----------------------------------------------------------------------
void loop()
{
  ethernet_ready_dhcp();          // Required in main loop to enable DHCP & HTTP response.
  //---------------------------------------------------------------------
  // On data receieved from rf12
  //---------------------------------------------------------------------
  #ifdef RF
  if (rf12_recvDone())
  {
    DEBUG_PRINT(".");
    /// if (rf12_crc == 0 && (rf12_hdr & RF12_HDR_CTL) == 0)
    if (rf12_crc == 0)
    ///if (true)   // Ignore checksums! 
    { 
      ledStatus(true);                        // Turn LED on to show receiving data
      emontx=*(Payload*) rf12_data;                                 // Get the payload
  
      DEBUG_PRINT("Got RF:");
      DEBUG_PRINTLN(millis()-milRF);

      dataReady = 1;                                                // Ok, data is ready
      milRF = millis();                                            // reset milRF timer
    }
  }
  #endif

  // If data or no too long since last posting
  if ((dataReady==1) || (millis() > milNext))
  {
    ethernet_ready_dhcp();     // Check DHCP is still OK.
    if (millis() > milNext) {
      ledStatus(false);                    // Turn LED off to show no RF data.
    }
    milNext = millis() + milMinInterval;
    // Send data to Pachube, but don't repeat too soon.
    if ((millis() - milPachube) > milPachubeInterval) {
      DEBUG_PRINTLN("");
      DEBUG_PRINT("Since:");
      DEBUG_PRINT(millis()+milMinInterval-milNext);
      DEBUG_PRINT(" Last RF:");
      DEBUG_PRINTLN(millis()-milRF);
      Pachube_Send();
      milPachube = millis(); 
      dataReady = 0;                        // reset dataReady
    }
  }
  if (millis() > milDisplay)
  {
    milDisplay = millis() + milDisplayInterval;
    iDisplay++;
    if (iDisplay > 2) {iDisplay = 0;}
    switch( iDisplay )
    {
      case 0: {
        DisplayData ("d", kWhDay);
        break;}
      case 1: {
        DisplayData ("r", kWh24);
        break;}
      case 2: {
        DisplayData ("C", fTemperature);
        break;}
    }
  }
}

void Pachube_Send()
{
  //----------------------------------------
  // 2) Send the data
  //----------------------------------------
    /* Datastreams:
0 = Gas, KW
1 = Indoor Temperature, Celcius
2 = Battery, Volts
3 = Messages Sent, count
4 = Pulses, count
5 = Meter Reading, m3
6 = kWh for the day
7 = kWh for the last 24 hours
*/

  str.reset();
  str.print("3,");
  post_count++;
  str.print(post_count);

  // Internal Temperature.
  #ifdef ONEWIRE
    sensors.requestTemperatures(); // Send the command to get temperatures
    fTemperature = -100;
    fTemperature = sensors.getTempCByIndex(0);  // First (only) sensor.
    if (fTemperature > -100 && fTemperature < 100) {
      DEBUG_PRINT("Int=");
      DEBUG_PRINTLN(fTemperature);
      dtostrf(fTemperature, 3, 1, fString);
      str.print("\r\n1,");
      str.print(fString);
    }
  #endif
  
  if (dataReady==1)                     // If data is ready: calculate data
  {
    float battVal = (float)emontx.supplyV * 3.3 / (float)1024;
    dtostrf(battVal, 4, 3, fString);
    str.print("\r\n2,");
    str.print(fString);

    str.print("\r\n4,");
    str.print(emontx.pulse);

    unsigned long milDiff;
    
    if (pulsePrev != 0)
    {
      milDiff = (millis() - timePrev);
      DEBUG_PRINT("Diff Time:");
      DEBUG_PRINT(milDiff);
      DEBUG_PRINT(" Pulse:");
      DEBUG_PRINT(emontx.pulse);      
      kW = (emontx.pulse - pulsePrev + iTest) * gasKWHM3 * 3600 * 1000 / (milDiff) / 100;
      DEBUG_PRINT(" kW:");
      DEBUG_PRINTLN(kW);
      dtostrf(kW, 3, 1, fString);
      str.print("\r\n0,");
      str.print(fString);
    }

    if (pulseStart == 0)
    {
      pulsePrev = emontx.pulse;
      pulseStart = emontx.pulse;
    }
    // Can only calculate longer values if we know the time.
    if (timeStatus() == timeSet)
    {
/*      if (day() != iDay))
      {
        DEBUG_PRINTLN("New day");
        iDay = day();
        pulseStart = pulsePrev;
        EEPROMWriteInt(24*2,pulseStart);
        EEPROMWriteInt(25*2,iDay);
      }
*/
      unsigned int timeNow;
      timeNow = timeDiff(now());
      int h;
      h = hour();
      if (iHour ==-1) {
        iHour = h;
      }
      if (h != iHour)
      {
        DEBUG_PRINT("New hour ");
        DEBUG_PRINT(h);
        DEBUG_PRINT(" ");
        DEBUG_PRINTLN(timeNow);
        // Set the value for the end of the previous hour.
        if (h == 0) {h = 23;}
        else {h = h-1;}
        EEPROMWriteInt(h*2,pulsePrev);
        EEPROMWriteInt((h+26)*2,timeNow);
        h = hour();
        iHour = h;
      }

      // Use the array to find the most appropriate previous pulses.
      unsigned int pulse;

      pulse = pulseValue(23, now());
      if (pulse == 0) {pulse = emontx.pulse;}
      kWhDay = (emontx.pulse - pulse) * gasKWHM3 / 100;
      DEBUG_PRINT("kWh day:");
      DEBUG_PRINTLN(kWhDay);
        ///kWhDay = (emontx.pulse - pulseStart) * gasKWHM3 / 100;
      dtostrf(kWhDay, 3, 1, fString);
      if (kWhDay < 150) {
        str.print("\r\n6,");
        str.print(fString);
      }
  
      // Use the value from the same hour yesterday
      pulse = pulseValue(h, now());
      if (pulse == 0) {pulse = emontx.pulse;}
      kWh24 = (emontx.pulse - pulse) * gasKWHM3 / 100;
      DEBUG_PRINT("kWh 24 hours:");
      DEBUG_PRINTLN(kWh24);
      dtostrf(kWh24, 3, 1, fString);
      if (kWh24 < 150) {
        str.print("\r\n7,");
        str.print(fString);
      }
    }

    pulsePrev = emontx.pulse;
    timePrev = millis();
  }

  #ifdef DEBUG
    Serial.println(str.buf);                                        // Print final json string to terminal
  #endif

  if (ethernet_ready_dhcp())
  {
    ///ledStatus(true);
    ethernet_send_post(PSTR(PACHUBEAPIURL),PSTR(PACHUBE_VHOST),PSTR(PACHUBEAPIKEY), PSTR("PUT "),str.buf);
    #ifdef DEBUG
      Serial.println("sent"); 
    #endif
    ///ledStatus(false);
  } else {
    DEBUG_PRINTLN("No DHCP!");
  }
  DEBUG_PRINTLN(datetimeString(now())); 
  DEBUG_PRINT(freeMemory());
  DEBUG_PRINTLN("=memory");
}

void DisplayData (char *sDisplay, float fDisplay)
{
  #ifdef USELEDSEG
    // Display on 7 segment LED
    LEDSEG.print("v\0");  // Clear contents
    if (fDisplay == 0) {
      LedSeg_DecimalPlace(1);
      sprintf(ledBuf, "%1s%3s", sDisplay, "00");
    } else if (fDisplay < 100) {
      LedSeg_DecimalPlace(1);
      sprintf(ledBuf, "%1s%3s", sDisplay, dtostrf(fDisplay*10, 3, 0, fString));
    } else {
      LedSeg_DecimalPlace(0);
      sprintf(ledBuf, "%1s%3s", sDisplay, dtostrf(fDisplay, 3, 0, fString));
    }
    DEBUG_PRINT("LED=");
    DEBUG_PRINTLN(ledBuf);
    LEDSEG.print(ledBuf);
  #endif
}

unsigned int pulseValue (int hIn, unsigned long timeIn)
{
  int i;
  int h;
  long diff;
  unsigned int ret;
  DEBUG_PRINT("Hour:");
  DEBUG_PRINT(hIn);
  DEBUG_PRINT(" Qrt:");
  DEBUG_PRINT(timeDiff(timeIn));
  DEBUG_PRINT(" > ");
  for (i == 0; i<24; i++) {
    h = i + hIn;
    if (h > 23) {h = h-24;}
    diff = (long)timeDiff(timeIn) - (long)timeHour[h];
    DEBUG_PRINT(h);
    DEBUG_PRINT(" ");
    DEBUG_PRINT(pulseHour[h]);
    DEBUG_PRINT(" ");
    DEBUG_PRINT(timeHour[h]);
    DEBUG_PRINT(" ");
    DEBUG_PRINT(diff);
    DEBUG_PRINT("; ");
    // Greater than 5 is a previous day so ignore.
    if (diff < 5) {
      ret = pulseHour[h];
      DEBUG_PRINT("< ");
      break;
    }
  }
  DEBUG_PRINTLN(ret);
  return ret;
}

unsigned int timeDiff (unsigned long timeIn)
{
  // Quarter days from 2012 - provides an integer (2 bytes) until 2055.
  unsigned long q;
  if (time2012 == 0) {
    /*
    tm.Year = 2012;
    tm.Month = 1;
    tm.Day = 1;
    time2012 = makeTime(tm);
    */
    time2012 = 1325376000L;   // 2012-01-01 ??
    DEBUG_PRINT("time2012:");
    DEBUG_PRINTLN(datetimeString(time2012));
  }
  q = (timeIn-time2012)/21600L;
  return q;
}

#ifdef USELEDSEG
void LedSeg_DecimalPlace (int precision)
{
  LEDSEG.print("w");  // Set decimal places etc.
  // Bits: 00, Apos, Colon, 1234., 123.4, 12.34, 1.234 
  if (precision == 0) {
    LEDSEG.print(B00000000,BYTE);  
  } else if (precision == 1) {
    LEDSEG.print(B00000100,BYTE);
  } else if (precision == 2) {
    LEDSEG.print(B00000010,BYTE);
  } else if (precision == 3) {
    LEDSEG.print(B00000001,BYTE);
  }
}
#endif

void ledStatus(int On)
{
  //On EmonTx input gets inverted by buffer
  #ifdef LEDLOW
    if (On == false) {
      digitalWrite(6,HIGH);
    }
    else {
      digitalWrite(6,LOW);
    }
  #else
    if (On == false) {
      digitalWrite(6,LOW);
    }
    else {
      digitalWrite(6,HIGH);
    }
  #endif
}

//This function will write a 2 byte integer to the eeprom at the specified address and address + 1
void EEPROMWriteInt(int p_address, int p_value)
{
  byte lowByte = ((p_value >> 0) & 0xFF);
  byte highByte = ((p_value >> 8) & 0xFF);

  EEPROM.write(p_address, lowByte);
  EEPROM.write(p_address + 1, highByte);
}

//This function will read a 2 byte integer from the eeprom at the specified address and address + 1
unsigned int EEPROMReadInt(int p_address)
{
  byte lowByte = EEPROM.read(p_address);
  byte highByte = EEPROM.read(p_address + 1);

  return ((lowByte << 0) & 0xFF) + ((highByte << 8) & 0xFF00);
}
