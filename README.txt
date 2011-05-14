GasLog
See here for results from my home: http://www.pachube.com/feeds/19886 
In my home the electricity and gas meters are in different rooms and are difficult to access, so I have taken the approach of using multiple Arduino Pro Minis with cheap RF transmitters and locate the main Ethernet Arduino and temperature sensor next to the Internet router. 
I used this low power Hall Effect sensor as it reduced power consumption from 1.5mA to 6µA. Soldering the SMD wasn’t as difficult as I thought. Note the hi-tech blu-tack used to hold the Hall sensor to the gas meter – it seems to work well enough.
Looking at the battery voltage before the 3.3V booster circuit, it seems that the sleep and interrupt approach seems to be working well for long battery life.  I may also unsolder the power LED as that should reduce the Mini’s consumption from 400µA to 100µA.
Future work will be to add a temperature sensor to the top (and bottom) of the hot water tank. Also add a relay to control a Velux (io-homecontrol) skylight as my home suffers from solar gain on sunny days.
http://uk.futureelectronics.com/en/technologies/semiconductors/analog/sensors/magnetic-hall-effect/Pages/3977865-MLX90248ESE.aspx 
 # 	Mfr. Part # 	Customer Part # 	Quantity 	Price (GBP) 	Ext. Price (GBP) 
1- 	MLX90248ESE 		6 	£0.2613 	£1.57 
 	MLX90248 Series 2.5 to 3.5 V SMT Micropower & Omnipolar Hall Switch - SOT-23-3L 		
2- 	MCP9803-M/MS 		6 	£0.8213 	£4.93 
 	MCP9803 Series MSOP-8 SMD 5.5 V 2-Wire High-Accuracy Temperature Sensor 		
