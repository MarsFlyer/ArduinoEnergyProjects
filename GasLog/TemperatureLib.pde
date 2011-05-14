/*
Local library to setup and get I2C Temperature readings.
*/

void temperatureSetup (int addr) {
  // Lego's Digital Temperature sensor.
  // It seems to be a Microchip MCP9803 (MCP9800 family)
  // The address is 0x98.
  // The temperature is in register 0x0 with
  //  byte 0 = 2's compliment degrees
  //  byte 1 = Decimal places (highest bits)
  // The default config in register 0x1 is 9-bits,0.5deg=0x0
  //  12-bits,0.0625deg=0x60, 11-bits,0.125deg=0x40, 10-bits,0.25deg=0x20
  Wire.beginTransmission(addr); 
                               // i2c adressing uses the high 7 bits
  Wire.send(0x01);             // sets register pointer
  Wire.send(0x60);             // set register value
  Wire.endTransmission();      // stop transmitting
  delay(70); 
}

int temperatureRead (int addr) {
///float temperatureRead (int addr) {
  int reading = 0;
  int iDeg;
  int iDec;
  float temperature;

  Wire.beginTransmission(addr); 
  Wire.send(0x00);             // sets register pointer
  Wire.endTransmission();      

  Wire.requestFrom(addr, 2);    // request 2 bytes

  if(2 <= Wire.available())    // if two bytes were received
  {
    reading = Wire.receive();  // receive high byte (overwrites previous reading)
    reading = reading << 8;    // shift high byte to be high 8 bits
    reading |= Wire.receive(); // receive low byte as lower 8 bits
    
    iDeg = reading/256;
    iDec = ((abs(reading-(iDeg*256))/16)*10)/16;
    // Debug
/*    Serial.print(" ");     
    Serial.print(iDeg);   // print the reading
    Serial.print(".");     
    Serial.println(iDec);   // print the reading */
    // Shift decimals 22.3 = 223
    temperature = iDeg*10+iDec;
    ///temperature = (float)iDeg+(float)iDec/(float)10;
    return temperature;
  }
}
