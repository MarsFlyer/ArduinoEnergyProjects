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
#ifdef DEBUG
  #define DEBUG_PRINT(x)      Serial.print (x)
  #define DEBUG_PRINTDEC(x)   Serial.print (x, DEC)
  #define DEBUG_PRINTLN(x)    Serial.println (x)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTDEC(x)
  #define DEBUG_PRINTLN(x)
#endif 
//---------------------------------------------------------------------
// RF12 link - JeeLabs
//---------------------------------------------------------------------
#include <Ports.h>
#include <RF12.h>

#define USELEDSEG
#ifdef USELEDSEG
  #include <NewSoftSerial.h>
  NewSoftSerial LEDSEG(4, 5);    // For 7 Segment LED display rx (not used), tx (used) 
#endif 

#define MYNODE 2            // node ID 30 reserved for base station
#define freq RF12_868MHZ     // frequency
#define group 5            // network group 

float gasKWHM3 = 11.13;   // From gas bill 

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
    char buf[150];
    private:
};
PacketBuffer str;

//---------------------------------------------------------------------
// Ethernet - Andrew Lindsay
//---------------------------------------------------------------------
#include <EtherShield.h>
byte mac[6] =     { 0x04,0x13,0x31,0x13,0x05,0x22};           // Unique mac address - must be unique on your local network

#define PACHUBE_VHOST "api.pachube.com"
#define PACHUBEAPIKEY "X-PachubeApiKey: 3VVQ2tTUXwV4agMe5HW3b7Ya9rWzJocSMZHa7FbFKbc" 
#define PACHUBEAPIURL "/v2/feeds/19886.csv"

byte server[4] = {173,203,98,29};

//---------------------------------------------------------------------

// Flow control varaiables
int dataReady=0;                                                  // is set to 1 when there is data ready to be sent
unsigned long lastRF;                                             // used to check for RF recieve failures
int post_count;                                                   // used to count number of ethernet posts that dont recieve a reply

int pulsePrev=-1;                    // Counters
long pulseStart=-1;
///long pulseStart=869;
unsigned long timePrev;

//---------------------------------------------------------------------
// Setup
//---------------------------------------------------------------------
void setup()
{
  Serial.begin(9600);
  Serial.println("Emonbase:NanodeRF ctonly");
  Serial.print("Node: "); Serial.print(MYNODE); 
  Serial.print(" Freq: "); Serial.print("433Mhz"); 
  Serial.print(" Network group: "); Serial.println(group);
  Serial.print("Posting to "); printIP(server); Serial.print(" "); Serial.println(PACHUBE_VHOST);

  
  ethernet_setup_dhcp(mac,server,80,8); // Last two: PORT and SPI PIN: 8 for Nanode, 10 for nuelectronics
  
  rf12_initialize(MYNODE, freq,group);
  lastRF = millis()-40000;                                        // setting lastRF back 40s is useful as it forces the ethernet code to run straight away
                                                                  // which means we dont have to wait to see if its working
  pinMode(6, OUTPUT); digitalWrite(6,LOW);                       // Nanode indicator LED setup, HIGH means off! if LED lights up indicates that Etherent and RFM12 has been initialize
  
  #ifdef USELEDSEG
    LEDSEG.begin(9600);
    LEDSEG.print("z");  // Full brightness
    LEDSEG.print("gas\0");
  #endif
}

//-----------------------------------------------------------------------
// Loop
//-----------------------------------------------------------------------
void loop()
{
  char ledBuf[5];
  char fString[10];

  digitalWrite(6,HIGH);    //turn inidicator LED off! yes off! input gets inverted by buffer
  //---------------------------------------------------------------------
  // On data receieved from rf12
  //---------------------------------------------------------------------
  if (rf12_recvDone() && rf12_crc == 0 && (rf12_hdr & RF12_HDR_CTL) == 0) 
  {
    digitalWrite(6,LOW);                                         // Flash LED on recieve ON
    emontx=*(Payload*) rf12_data;                                 // Get the payload

    dataReady = 1;                                                // Ok, data is ready
    lastRF = millis();                                            // reset lastRF timer
    digitalWrite(6,HIGH);                                          // Flash LED on recieve OFF
  }
  
  ethernet_ready_dhcp();               // Keep DHCP alive
  //----------------------------------------
  // 2) Send the data
  //----------------------------------------
  //if (ethernet_ready_dhcp() && dataReady==1)                     // If ethernet and data is ready: send data
  if (dataReady==1)                     // If data is ready: display & send data
  {
    /* Datastreams:
0 = Gas, KW
1 = Indoor Temperature, Celcius
2 = Battery, Volts
3 = Messages Sent, count
4 = Pulses, count
5 = Meter Reading, m3
6 = kWh for the day
*/
    str.reset();
    str.print("3,");
    post_count++;
    str.print(post_count);

    float battVal = (float)emontx.supplyV * 3.3 / (float)1024;
    int integer = floor(battVal);
    int mantissa = floor(1000.0f*(battVal- integer));
    str.print("\r\n2,");
    str.print(integer);
    str.print(".");
    str.print(mantissa);

    str.print("\r\n4,");
    str.print(emontx.pulse);

    float kW;
    unsigned long timeDiff;
    int iTest;
    
    // For testing:
    iTest = 0;
    
    if (pulsePrev != -1)
    {
      timeDiff = (millis() - timePrev);
      DEBUG_PRINT("Diff Time:");
      DEBUG_PRINT(timeDiff);
      DEBUG_PRINT(" Pulse:");
      DEBUG_PRINT(emontx.pulse - pulsePrev);      
      kW = (emontx.pulse - pulsePrev + iTest) * gasKWHM3 * 3600 * 1000 / (timeDiff) / 100;
      DEBUG_PRINT(" kW:");
      DEBUG_PRINTLN(kW);
      ftoa(fString, kW, 1);
      str.print("\r\n0,");
      str.print(fString);
    }
    pulsePrev = emontx.pulse;
    timePrev = millis();

    if (pulseStart == -1)
    {
      pulseStart = emontx.pulse;
    }
    kW = (emontx.pulse - pulseStart) * gasKWHM3 / 100;
    DEBUG_PRINT(" kW:");
    DEBUG_PRINTLN(kW);
    ftoa(fString, kW, 1);
    str.print("\r\n6,");
    str.print(fString);

    #ifdef USELEDSEG
      // Display on 7 segment LED
      LEDSEG.print("v\0");  // Clear contents
      if (kW < 100) {
        LedSeg_DecimalPlace(1);
        sprintf(ledBuf, "d%3s", ftoa(fString, kW*10, 0));
      } else {
        LedSeg_DecimalPlace(0);
        sprintf(ledBuf, "d%3s", ftoa(fString, kW, 0));
      }
      LEDSEG.print(ledBuf);
      DEBUG_PRINTLN(ledBuf);
    #endif
    
    #ifdef DEBUG
    Serial.println(str.buf);                                        // Print final json string to terminal
    #endif
    
    if (ethernet_ready_dhcp())
    {
      ethernet_send_post(PSTR(PACHUBEAPIURL),PSTR(PACHUBE_VHOST),PSTR(PACHUBEAPIKEY), PSTR("PUT "),str.buf);
      #ifdef DEBUG
      Serial.println("sent"); 
      #endif
    }
    dataReady = 0;                        // reset dataReady
  }
  
}

#ifdef USELEDSEG
  void LedSeg_DecimalPlace (int precision) {
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

// Float support is hard on arduinos
// (http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1164927646) with tweaks
char *ftoa(char *a, double f, int precision)
{
  //TEST_PRINTLN(f);
  long p[] = {0,10,100,1000,10000,100000,1000000,10000000,100000000};
  char *ret = a;
  long heiltal = (long)f;
  
  itoa(heiltal, a, 10);
  while (*a != '\0') a++;
  if (precision > 0) {
    *a++ = '.';
    long desimal = abs((long)((f - heiltal) * p[precision]));
    itoa(desimal, a, 10);
  }
  return ret;
}





