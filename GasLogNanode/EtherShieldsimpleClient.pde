//--------------------------------------------------------
//   EtherShield examples: simple client functions
//
//   simple client code layer:
//
// - ethernet_setup(mac,ip,gateway,server,port)
// - ethernet_ready() - check this before sending
//
// - ethernet_setup_dhcp(mac,serverip,port)
// - ethernet_ready_dhcp() - check this before sending
//
// - ethernet_setup_dhcp_dns(mac,domainname,port)
// - ethernet_ready_dhcp_dns() - check this before sending
//
//   Posting data within request body:
// - ethernet_send_post(PSTR(PACHUBEAPIURL),PSTR(PACHUBE_VHOST),PSTR(PACHUBEAPIKEY), PSTR("PUT "),str);
// 
//   Sending data in the URL
// - ethernet_send_url(PSTR(HOST),PSTR(API),str);
//
//   EtherShield library by: Andrew D Lindsay
//   http://blog.thiseldo.co.uk
//
//   Example by Trystan Lea, building on Andrew D Lindsay's examples
//
//   Projects: Nanode.eu and OpenEnergyMonitor.org
//   Licence: GPL GNU v3
//--------------------------------------------------------

#define DATESET
#ifdef DATESET
  #include <Time.h>          // For time sync
#endif

int data_recieved = 0;

byte* mymac;
static uint8_t myip[4] =      { 0,0,0,0 };
static uint8_t mynetmask[4] = { 0,0,0,0 };
byte* websrvip;
static uint8_t gwip[4] =      { 0,0,0,0 };
static uint8_t dnsip[4] =     { 0,0,0,0 };
static uint8_t dhcpsvrip[4] = { 0,0,0,0 };

char* webserver_vhost;

EtherShield es=EtherShield();

#define BUFFER_SIZE 500
static uint8_t buf[BUFFER_SIZE+1];
uint16_t dat_p;
int plen = 0;

int port;

long lastDnsRequest = 0L;
long lastDhcpRequest = 0L;

int retstat, lastretstat;

boolean gotIp = false;

static int8_t dns_state=DNS_STATE_INIT;

void printIP( uint8_t *buf ) {
  for( int i = 0; i < 4; i++ ) {
    Serial.print( buf[i], DEC );
    if( i<3 )
      Serial.print( "." );
  }
}

//------------------------------------------------------------------------------------------------
// DHCP only
//------------------------------------------------------------------------------------------------
void ethernet_setup_dhcp(byte* in_mymac,byte* in_websrvip, int in_port,int spipin)
{
  mymac = in_mymac;
  websrvip = in_websrvip;
  
  es.ES_enc28j60SpiInit();
  es.ES_enc28j60Init(mymac,spipin);
  es.ES_client_set_wwwip(websrvip);  // target web server
  port = in_port;
}

int ethernet_ready_dhcp()
{
  uint8_t dhcpState = 0;
  dhcpState = es.ES_dhcp_state();
  
  plen = es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf);
  dat_p=es.ES_packetloop_icmp_tcp(buf,plen);
  
  if (dat_p==0 && dhcpState == DHCP_STATE_OK)
  {
    if (gotIp)
    {
      return 1;
    }
    else
    {
      #ifdef DEBUG
      // Display the results:
      Serial.print( "My IP: " );    printIP( myip );       Serial.println();
      Serial.print( "Netmask: " );  printIP( mynetmask );  Serial.println();
      Serial.print( "DNS IP: " );   printIP( dnsip );      Serial.println();
      Serial.print( "GW IP: " );    printIP( gwip );       Serial.println();
      #endif
      gotIp = true;

      //init the ethernet/ip layer:
      es.ES_init_ip_arp_udp_tcp(mymac, myip, port);

      // Set the Router IP
      es.ES_client_set_gwip(gwip);  // e.g internal IP of dsl router

      // Set the DNS server IP address if required, or use default
      es.ES_dnslkup_set_dnsip( dnsip );
      
      //dhcp_count++;
    }
  }

  if (dat_p==0 && dhcpState != DHCP_STATE_OK) 
  {   
    // 1) Send a DHCP request every 10s
    if (millis() > (lastDhcpRequest + 10000L) ){
      #ifdef DEBUG
      Serial.println("Sending DHCP request");
      #endif
      es.ES_dhcp_start( buf, mymac, myip, mynetmask,gwip, dnsip, dhcpsvrip );
      lastDhcpRequest = millis();
      gotIp = false;
    }
      
    // 2) on answer
    lastretstat = retstat;
    retstat = es.ES_check_for_dhcp_answer( buf, plen);
    #ifdef DEBUG
    if (retstat!=lastretstat) {Serial.print("retstat "); Serial.println(retstat);}
    #endif
  }
  return 0;
}
    
//------------------------------------------------------------------------------------------------
// Send
//------------------------------------------------------------------------------------------------
/*
void ethernet_send_url(char * hoststr, char * urlbuf,char * urlbuf_varpart)
{
  data_recieved = 0;
  es.ES_client_browse_url(urlbuf,urlbuf_varpart,hoststr,&browserresult_callback);
}
*/
int posLine = 0;

void ethernet_send_post(char * urlbuf,char * hoststr,char * additionalheaderline,char * method,char * postval)
{
  es.ES_client_http_post(urlbuf,hoststr,additionalheaderline,method,postval, &browserresult_callback);
}

void browserresult_callback(uint8_t statuscode,uint16_t datapos) 
{
  if (datapos != 0)
  {
    uint16_t pos = datapos;
    while (buf[pos])
    {
      #ifdef DEBUG
        Serial.print(buf[pos]);
      #endif

      char c = buf[pos];
      if (c == '\r' || c == '\n')
      {
        if (pos > posLine +5)
        {
          #ifdef DATESET
            if ((buf[posLine] == 'D') && (buf[posLine+1] == 'a') && (buf[posLine+2] == 't') && (buf[posLine+3] == 'e') && (buf[posLine+4] == ':')) { 
              //Date: Wed, 16 Mar 2011 22:32:39 GMT\r\n
              int hr = intPart(buf,posLine+23,posLine+25);
              int min = intPart(buf,posLine+26,posLine+28);
              int sec = intPart(buf,posLine+29,posLine+31);
              int day = intPart(buf,posLine+11,posLine+13);
              //int month = 11; 
              int month = intMonth(buf,posLine+14,posLine+17);
              int yr = intPart(buf,posLine+18,posLine+22);
              setTime(hr,min,sec,day,month,yr);
              #ifdef DEBUG
                Serial.println("");
                Serial.print(">sync:");
                Serial.print(datetimeString(now()));
              #endif
            }
          #endif
        }
        posLine = pos+1;
      }

      pos++;
    }
    data_recieved = 1;
  }
}

int reply_recieved()
{
  return data_recieved;
}

/*
Example results
HTTP/1.1 200 OK
Date: Mon, 21 Nov 2011 09:30:51 GMT
Content-Type: text/plain; charset=utf-8
Connection: close
X-Pachube-Logging-Key: logging.8VwV6gqSSgvfDWxxMTcT
X-PachubeRequestId: 9d8963627f695fd5db1d021216a3116a6d7ac4b0
Cache-Control: max-age=0
Content-Length: 1
Age: 0
Vary: Accept-Encoding
*/

#ifdef DATESET
  // Date Functions:
  char bufTime[30] = "";
  char bufMonth[38] = "JanFebMarAprMayJunJulAugSepOctNovDec";
  
  int intPart(uint8_t* in, int iFrom, int iTo){
    int i=0;
    while(iFrom < iTo)  // go into assignment loop
    {
      bufTime[i++] = in[iFrom++];  // assign them
    }
     // now append a terminator
    bufTime[i] = '\0';
    return atoi(bufTime);
  }    
  
  int intMonth(uint8_t* in, int iFrom, int iTo){
    int i=0;
    int m=0;
    while(iFrom < iTo)  // go into assignment loop
    {
      bufTime[i++] = in[iFrom++];  // assign them
    }
    for(int j = 0; j<36; j=j+3)
    {
      m++;
      if (bufMonth[j] != bufTime[0]) {continue;}
      if (bufMonth[j+1] != bufTime[1]) {continue;}
      if (bufMonth[j+2] != bufTime[2]) {continue;}
      return m; // or return i+1, depending on what you want
    }
    return 0;
  }
  
  // Display functions:
  char* datetimeString(unsigned long t){
    sprintf(bufTime,"%4d-%02d-%02dT%02d:%02d:%02d\0", year(t), month(t), day(t), hour(t), minute(t), second(t)); 
    return bufTime;
  }
#endif

