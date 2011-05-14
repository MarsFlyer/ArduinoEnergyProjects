/* Pachube Library 
GET
PUT
*/

/* Define variables i n the code
String httpReq;
byte line_cursor;
String line;
///String results;
String dateStr;
char dateChar[5];
int  dateInt;
*/
long lastConnectionTime;

#define LINE_BUFF_SIZE 79

#define MAX_STRING 100
/*
const char pachubeAPI[]   PROGMEM = "XXX"; // fill in your API key 
const char pachubeFeed[]  PROGMEM = "19886";    // this is the ID of the remote Pachube feed that you want to connect to

const char httpHost[]     PROGMEM = ".csv HTTP/1.1\r\nHost: api.pachube.com\r\nX-PachubeApiKey: ";
const char httpAgent[]    PROGMEM = "\r\nUser-Agent: Arduino\r\n\r\n";
const char httpContent[]  PROGMEM = "\r\nContent-Type: text/csv";
///const char httpContent[] PROGMEM = "\r\nContent-Type: application/x-www-form-urlencoded";
const char httpLength[]   PROGMEM = "\r\nUser-Agent: Arduino\r\nContent-Length: ";
*/
//char stringBuffer[MAX_STRING];

String pachube(char* verb, char* dataStr)
{
  // The data needs line feeds.
  // Example: "0,8\r\n1,21.2\r\n";

  int iLen = strlen(dataStr);
  int iAttempts = 0;
  while(iAttempts++ < 3)
  {
    TEST_PRINT(freeMemory());
    TEST_PRINT(" Connect ");
    TEST_PRINTLN(iAttempts);
    
/*    if (iAttempts >= 2) {
      ethernetInit();
      TEST_PRINT(freeMemory());
      TEST_PRINTLN(" Reset.");
      digitalWrite(resetPin, false);
      delay(200);
      digitalWrite(resetPin, true);
      delay(2000);
      Ethernet.begin(mac, ip);
      delay(250);
      iConnections -= 5;
    } */
    ///else {continue;}

    if (!client.connect()) {
      ///TEST_PRINTLN("connect failed");
      if (iAttempts >= 2) {
        ethernetInit();
      }
      else {
        delay(1000);
      }
      continue;
    }
    DEBUG_PRINTLN("connected");
      
    if (verb == "GET")
    {
      DEBUG_PRINT(freeMemory());
      DEBUG_PRINTLN(" GET");
  /*    client.print("GET /api/");
      client.print(getString(pachubeFeed)); 
      client.print(getString(httpHost)); 
      client.print(getString(pachubeAPI));
      client.print(getString(httpAgent));
 */   } 
    else if (verb == "PUT")
    {
      // send the HTTP PUT request. 
      DEBUG_PRINT(freeMemory());
      DEBUG_PRINTLN(" PUT");
      if (1==1) {
/*
        DEBUG_PRINT("PUT /v2/feeds/");
        DEBUG_PRINT(getString(pachubeFeed)); 
        DEBUG_PRINT(getString(httpHost));
        DEBUG_PRINT(getString(pachubeAPI));
        DEBUG_PRINT(getString(httpContent));
        DEBUG_PRINT(getString(httpLength));
        DEBUG_PRINTDEC(iLen);
        // There needs to be an empty line after the data.
        ///Serial.print("\r\nConnection: close\r\n\r\n");
        DEBUG_PRINT("\r\n\r\n");
        DEBUG_PRINT(dataStr);
        DEBUG_PRINT("\r\n\r\n");
*/
        client.print("PUT /v2/feeds/19886.csv HTTP/1.1\r\nHost: api.pachube.com\r\nX-PachubeApiKey: ");
        client.print("XXX");
        client.print("\r\nContent-Type: text/csv\r\nUser-Agent: Arduino\r\nContent-Length: ");
        client.print(iLen, DEC);
        // There needs to be an empty line after the data.
        ///client.print("\r\nConnection: close\r\n\r\n");
        client.print("\r\n\r\n");
        client.print(dataStr);
        client.print("\r\n\r\n");
      }
      else {
/*        httpSend("PUT /v2/feeds/");
        httpSend(getString(pachubeFeed)); 
        httpSend(getString(httpHost));
        httpSend(getString(pachubeAPI));
        httpSend(getString(httpContent));
        httpSend(getString(httpLength));
        httpSend(iLen);
        // There needs to be an empty line before and after the data.
        httpSend("\r\n");
        httpSend(dataStr);
        httpSend("\r\n\r\n");
*/      }

      TEST_PRINT(freeMemory());
      TEST_PRINTLN(" Sent.");
    }

    while (client.connected())  // Get response.
    {
      int line_cursor = 0;
      ///String line = "";
      while (client.connected())  // Per line
      {
        if (client.available())
        {
          char c = client.read();
          TEST_PRINT(c);
          if (c == '\n') {buf2[line_cursor] = '\0'; break;}
          // Ignore CRs
          if (c != '\r')
          {
            ///line += c;
            buf2[line_cursor] = c;
            line_cursor++;
            if (line_cursor >= LINE_BUFF_SIZE) {break;}
          }
        }
      }
      ///Serial.println(line);
      if (line_cursor == 0) {break;}
      ///results += line;   // Only send the actual result lines.
      ///if (line.startsWith("Date:")) { 
      if ((buf2[0] == 'D') && (buf2[1] == 'a') && (buf2[2] == 't') && (buf2[3] == 'e') && (buf2[4] == ':')) { 
        //Date: Wed, 16 Mar 2011 22:32:39 GMT\r\n
        int hr = intPart(buf2,23,25);
        int min = intPart(buf2,26,28);
        int sec = intPart(buf2,29,31);
        int day = intPart(buf2,11,13);
        int month = 4; // = intPart(line,14,17)
        int yr = intPart(buf2,18,22);
        setTime(hr,min,sec,day,month,yr);
        DEBUG_PRINT(freeMemory());
        DEBUG_PRINTLN(" Sync:");
        ///TEST_PRINTLN(datetimeString(now()));

        // note the time that the connection was made:
        long lastConnectionTime = millis();
        iConnections++;
        iAttempts = 9; // No need to try again.
      }
      ///line = "";
    }

    DEBUG_PRINTLN("disconnecting.");
    client.stop();
  }
}

int intPart(char* in, int iFrom, int iTo){
  char buf3[30] = "";
  int i=0;
  while(iFrom < iTo)  // go into assignment loop
  {
    buf3[i++] = in[iFrom++];  // assign them
  }
   // now append a terminator
  buf3[i] = '\0';
  return atoi(buf3);
}    

char* getString(const char* str) {
  char stringBuffer[MAX_STRING];
  strcpy_P(stringBuffer, (char*)str);
  ///TEST_PRINT(stringBuffer);
  return stringBuffer;
}

void httpSend(String in) {
  client.print(in);
  TEST_PRINT(in);
}

void ethernetInit()
{
  int ms = 1000;
  TEST_PRINT(freeMemory());
  TEST_PRINT(" Ethernet init...");
  wdt_reset();
  pinMode(resetPin, OUTPUT);      // sets the digital pin as output
  digitalWrite(resetPin, LOW);
  delay(ms*4);  //for ethernet chip to reset - needs ~4 seconds to properly reset.
  digitalWrite(resetPin, HIGH);
  pinMode(resetPin, INPUT);      // sets the digital pin input
  delay(ms);  //for ethernet chip to reset
  wdt_reset();
  Ethernet.begin(mac,ip,gateway,subnet);
  delay(ms);  //for ethernet chip to reset
  Ethernet.begin(mac,ip,gateway,subnet);
  delay(ms);  //for ethernet chip to reset
  ///TEST_PRINT(freeMemory());
  TEST_PRINTLN(" done");
}
