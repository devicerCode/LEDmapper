/**
 LED mapping creator
 Peter Brittain 2018
 info@devicer.net
 Create mappings automatically from a webcam pointed at your addressable LED setup
 Works with LEDmap arduino code
 Contains code from blobDetect examples by [Julien 'v3ga' Gachadoat](http://www.v3ga.net)
 http://www.v3ga.net/processing/BlobDetection/
 */

import processing.video.*;  //import processing video library - for webcam/video
import controlP5.*;  //import controlP5 library for GUI elements
import java.util.*;      //import java utils - for list class
import processing.serial.*;     // import the Processing serial library
import blobDetection.*;    //import blob detect library

Capture cam;

ControlP5 cp5;
Button automapButton;
int brightnessSlider = 0;
int threshold = 0;
Button saveMapping;
RadioButton outputChoice;
boolean showAllLEDs;


String[] seriallist;
int SERIAL_SPEED = 115200;
boolean serialEnabled = false;
Serial myPort;      // The serial port


PImage blobInput;

PGraphics output;
//blob detect stuff
BlobDetection theBlobDetection;
boolean newFrame = false;
long WAIT_TIME = 390; //delay between led detections - increase for stability if camera auto-balances
long lastTime = 0;//stores last time blob detect was run
long startTime = 0;//time automap started
int ledIndex = 0; //store position of current light index
boolean automap = false;
boolean automapLastVal = false;
//camera stuff
String[] cameras;
boolean cameraEnabled = false;
int displayAreaWidth = 640;
int displayAreaHeight = 480;


//LED stuff
boolean ledDeviceConnected = false; //used to mark if connected device seems to be led controller
int NUM_LEDS = 0; //main led count
boolean ledsReady = false; //used to start sending to leds if true
byte[] lightsarray;


map2d mapping;

void setup() {
  size(1200, 800);
  cp5 = new ControlP5(this);

  cameras = Capture.list();
  cameras = append(cameras, "NO CAMERA");

  seriallist = Serial.list();
  seriallist = append(seriallist, "NO SERIAL");
  output = createGraphics(displayAreaWidth, displayAreaHeight);
  blobInput = new PImage(displayAreaWidth/2, displayAreaWidth/2); //small so blob detect is faster, around 320x240 is generally enough

  if (cameras == null) {
    println("Didn't find a camera, trying anyway...");
    cam = new Capture(this, displayAreaWidth, displayAreaHeight);
  } 
  if (cameras.length == 0) {
    println("There are no cameras available for capture.");
    cameras = append(cameras, "NO CAMERA");
  } else {
    println("Available cameras:");
    printArray(cameras);
  }

  List<String> availableCamsList = Arrays.asList(cameras);
  List<String> availablePortsList = Arrays.asList(seriallist);   

  //Create SerialPorts select drop down list (ScrollableList)
  cp5.addScrollableList("SerialPorts")
    .setPosition(displayAreaWidth+10, 140)
    .setSize(280, 100)
    .setBarHeight(20)
    .setItemHeight(20)
    .addItems(availablePortsList)
    .setOpen(true) //set open for convenience - saves a click opening it.
    ;
  //Create Camera select drop down list (ScrollableList)
  cp5.addScrollableList("Cameras")
    .setPosition(displayAreaWidth+10, 20)
    .setSize(280, 100)
    .setBarHeight(20)
    .setItemHeight(20)
    .addItems(availableCamsList)
    .setOpen(true)
    ;
  cp5.addSlider("brightnessSlider")
    .setPosition(displayAreaWidth+10, 270)
    .setRange(0, 255)
    .setSize(200, 20)
    .setColorForeground(color(255, 0, 0))
    .setColorActive(color(255, 0, 0))
    .setValue(16)
    .setCaptionLabel("Set LED brightness")
    ;
  cp5.addSlider("threshold")
    .setPosition(displayAreaWidth+10, 300)
    .setRange(0, 255)
    .setSize(200, 20)
    .setValue(250);
  ;
  automapButton = cp5.addButton("automap")
    .setPosition(displayAreaWidth+10, 330)
    .setSize(50, 40)
    ;
  saveMapping = cp5.addButton("saveMapping")
    .setPosition(displayAreaWidth+10, 430)
    .setSize(80, 40)
    .setCaptionLabel("Save mapping as...")
    ;
  cp5.addButton("showAllLEDs")
    .setCaptionLabel("Show all LEDs")
    .setPosition(displayAreaWidth+130, 330)
    .setSize(80, 40)
    ;
  outputChoice = cp5.addRadioButton("selectOutputType")
    .setPosition(displayAreaWidth+10, 380)
    .setSize(40, 20)
    //maybe not doing anything debug delete this when confirmed
    .setItemsPerRow(1)
    .setSpacingColumn(20)
    .addItem("byte mapping (0-255)", 0)
    .addItem("int mapping (0-65536)", 1)
    ;
  theBlobDetection = new BlobDetection(blobInput.width, blobInput.height);
  theBlobDetection.setPosDiscrimination(true); //set to detect light not dark
  theBlobDetection.setThreshold(0.2f);
  outputChoice.activate(0);
}

void draw() {
  background(128);
  theBlobDetection.setThreshold(threshold/255.0);
  if ((cam != null) &&(newFrame==true)) {
    newFrame=false;
    output.beginDraw();
    output.copy(cam, 0, 0, cam.width, cam.height, 0, 0, output.width, output.height);
    blobInput.copy(cam, 0, 0, cam.width, cam.height, 0, 0, blobInput.width, blobInput.height);
    blobInput.filter(BLUR, 3);
    theBlobDetection.computeBlobs(blobInput.pixels);
    drawBlobsAndEdges(true, true);
    if (mapping != null) {
      mapping.drawPositions(output.width, output.height);
    }
    output.endDraw();
    newFrame = false;
  }
  image(output, 0, 0, displayAreaWidth, displayAreaHeight);

  if (ledsReady) {
    clearLEDs();
    if (automap) {
      flashStatusOn();
      if (ledIndex >= NUM_LEDS) {
        stopAutoMap();
      } else {
        doSingleLED(ledIndex);
        myPort.write(lightsarray);
        if ((millis()-startTime>WAIT_TIME*2)&&(millis()-lastTime>WAIT_TIME)) {
          PVector testVector = getLightPositionBlobDet();
          mapping.setCoord(ledIndex, testVector);
          ledIndex++;
          lastTime = millis();
        }
      }
    } else {
      if (showAllLEDs) {
        fillLEDs((byte)brightnessSlider);
      } else {
        if (mapping == null) {
          doSingleLED(0);
        } else {
          showLedUnderMouse();
        }
      }
    }
    myPort.write(lightsarray);
  }
  drawLEDsSizeIndicator();
}

void brightnessSlider(int theBrightness) {
  brightnessSlider = int(theBrightness);
}

void showAllLEDs() {
  showAllLEDs = !showAllLEDs;
}


void automap() {
  if ((ledsReady == true)&&(cameraEnabled==true)) {
    automap = !automap;
    if ((automap==true)&&(automapLastVal==false)) {
      startTime = millis();
      ledIndex = 0;
      println("automap started/reset");
    }
    automapLastVal = automap;
    if ((automap==false)&&(automapLastVal==true)) {
      stopAutoMap();
    }
  }
}


void stopAutoMap() {
  automapLastVal = false;
  automap = false;
  flashStatusOff();
}

void flashStatusOn() {
  if (((millis()/WAIT_TIME)%2)==0) {
    automapButton.setColorBackground(color(255, 0, 0));
  } else {
    automapButton.setColorBackground(color(0, 45, 90)); //default colour
  }
}


void flashStatusOff() {
  automapButton.setColorBackground(color(0, 45, 90));
}


void SerialPorts(int n) {
  //Callback from cp5 - Runs every time a new selection is made

  String selectedPort = cp5.get(ScrollableList.class, "SerialPorts").getItem(n) .get("name").toString();
  println(selectedPort);
  if (selectedPort.equals("NO SERIAL")) {
    //INFO
    println("No serial selected");
    if (myPort != null) {
      myPort.stop();
    }
    serialEnabled = false;
    ledDeviceConnected = false;
    ledsReady = false;
    NUM_LEDS = 0;
  } else {
    //Try to connect to selected serial port...
    //needs better protection from failing at random points? (disconnects mostly)
    //disable old port if present before opening new one.
    if (myPort != null) {
      myPort.stop();
      serialEnabled = false;
      ledDeviceConnected = false;
      ledsReady = false;
      NUM_LEDS = 0;
      //INFO
      println("Port Existed so disabled");
    }
    //INFO
    println("Enabling serial port");
    myPort = new Serial(this, selectedPort, SERIAL_SPEED);
    myPort.bufferUntil('\n');
    serialEnabled = true;
    //INFO
    println("Port Should now be open...");
  }
}


void Cameras(int n) {
  //Callback from cp5 - Runs every time a new selection is made
  String selectedCamera = cp5.get(ScrollableList.class, "Cameras").getItem(n).get("name").toString();
  println(selectedCamera);
  if (selectedCamera.equals("NO CAMERA")) {
    //INFO
    println("No camera selected");
    cameraEnabled = false;
  } else {
    if (cam != null) {
      cam.stop();
      cameraEnabled = false;
    }
    cam = new Capture(this, cameras[n]);
    cam.start();
    cameraEnabled = true;
  }
}


void serialEvent(Serial myPort) {
  // read the serial buffer:
  String myString = myPort.readStringUntil('\n');
  // if you got any bytes other than the linefeed:
  if (myString != null) {
    myString = trim(myString);
    // split the string at the commas
    // and convert the sections into integers:
    String receivedData[] = (split(myString, '='));
    //debug
    println(receivedData[0]);
    if ((ledDeviceConnected == true)&&(NUM_LEDS == 0)) {
      //if there's a connected device but no led count yet then 
      //should be getting it back from sending query below - but on next loop
      //or later...
      //INFO
      println("Getting NUM_LEDS");
      if (receivedData[1]!=null) {
        NUM_LEDS = int(receivedData[1]);
        //INFO
        println("NUM_LEDS: ", NUM_LEDS);
        lightsarray = new byte[NUM_LEDS*3];
        ledsReady = true;
        mapping = new map2d(NUM_LEDS, displayAreaWidth, displayAreaHeight);
      }
    }
    if ((receivedData[0].equals("LEDmap"))&&(ledDeviceConnected == false)) {
      //Selected Device is likely running the right code...
      //Send byte to then get NUM_LEDS from controller
      //INFO
      println("Succesfully connected to LED device");
      ledDeviceConnected = true;
      //send something to controller side to ask for led count
      //in this case 'A' to keep things simple, no problems with this so far!
      myPort.write("A");
    }
  }
}


void captureEvent(Capture cam)
{
  cam.read();
  newFrame = true;
}


void drawBlobsAndEdges(boolean drawBlobs, boolean drawEdges)
{
  //this code taken from  blobDetection examples as credited above
  output.noFill();
  Blob b;
  EdgeVertex eA, eB;
  for (int n=0; n<theBlobDetection.getBlobNb(); n++)
  {
    b=theBlobDetection.getBlob(n);
    if (b!=null)
    {
      // Edges
      if (drawEdges)
      {
        output.strokeWeight(3);
        output.stroke(0, 255, 0);
        for (int m=0; m<b.getEdgeNb(); m++)
        {
          eA = b.getEdgeVertexA(m);
          eB = b.getEdgeVertexB(m);
          if (eA !=null && eB !=null)
            output.line(
              eA.x*output.width, eA.y*output.height, 
              eB.x*output.width, eB.y*output.height
              );
        }
      }

      // Blobs
      if (drawBlobs)
      {
        output.strokeWeight(1);
        output.stroke(255, 0, 0);
        output.rect(
          b.xMin*output.width, b.yMin*output.height, 
          b.w*output.width, b.h*output.height
          );
      }
    }
  }
}


PVector getLightPositionBlobDet() {
  PVector light = new PVector(0, 0);
  if (theBlobDetection.getBlobNb()>0) {
    Blob tempblob = theBlobDetection.getBlob(0);
    light.x = tempblob.x;
    light.y = tempblob.y;
  } else {
    light.x = -1;
    light.y = -1;
  }
  return(light);
}


void fillLEDs(byte value) {
  for (int i=0; i<lightsarray.length; i++) {
    lightsarray[i] = value;
  }
}

void clearLEDs() {
  for (int i=0; i<lightsarray.length; i++) {
    lightsarray[i] = 0;
  }
}

void doSingleLED(int index) {
  for (int i=0; i<lightsarray.length; i++) {
    int thisIndex = int(i/3);
    if (thisIndex == index) {
      lightsarray[i] = byte(brightnessSlider);
    }
  }
}


void saveMapping() {
  selectOutput("Select a file to write to:", "selectOutput");
}


void selectOutput(File selection) {
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    //INFO
    println("User selected " + selection.getAbsolutePath());
    int radioValue = (int)outputChoice.getValue();
    switch(radioValue) {
    case 0:
      mapping.saveMappingStructStyle(selection.getAbsolutePath(), 255);
      break;
    case 1:
      mapping.saveMappingStructStyle(selection.getAbsolutePath(), 65536);
      break;
    default:
      break;
    }
  }
}


void showLedUnderMouse() {
  float radius = 30;
  PVector mousePos = new PVector(mouseX, mouseY);
  if ((mouseX>=0)&&(mouseX<displayAreaWidth)&&(mouseY>=0)&&(mouseY<displayAreaHeight)) {
    if (mapping != null) {
      for (int i=0; i<mapping.mapCoords.length; i++) {
        if (mapping.mapCoords[i] != null) {
          PVector screenSizeCoords = new PVector(mapping.mapCoords[i].x*displayAreaWidth, mapping.mapCoords[i].y*displayAreaHeight);
          float d = mousePos.dist(screenSizeCoords);
          if (d<radius) {
            //light led up if near current mouse pos
            doSingleLED(i);
          }
        }
      }
    }
  }
}

void drawLEDsSizeIndicator(){
   if (NUM_LEDS != 0) {
    stroke(255);
    textSize(20);
    text(NUM_LEDS + " LEDs", displayAreaWidth+220, 350);
  }
}