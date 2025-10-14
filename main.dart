import 'package:flutter/material.dart';

/// Flutter code sample for [ElevatedButton].

void main() => runApp(const ElevatedButtonIconSliderApp());

class ElevatedButtonIconSliderApp extends StatelessWidget {
  const ElevatedButtonIconSliderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Center(child: Text('Elevated Button, Icon, Icon Button, and Sliders'))),
        body: const ElevatedButtonTest(),
      ),
    );
  }
}

class ElevatedButtonTest extends StatefulWidget {
  const ElevatedButtonTest({super.key});

  @override
  State<ElevatedButtonTest> createState() => _ElevatedButtonTestState();
}


class _ElevatedButtonTestState extends State<ElevatedButtonTest> {
  double _currentSliderPrimaryValue = 0.2;
  double _currentSliderSecondaryValue = 0.5;
  double _sliderVolumeValue = 0;
  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = ElevatedButton.styleFrom(textStyle: const TextStyle(fontSize: 20)); //default elevated button
    final ButtonStyle raised = ElevatedButton.styleFrom(foregroundColor: Colors.black87,backgroundColor: Colors.grey[300], //previous raised button style
    minimumSize: Size(88, 36),padding: EdgeInsets.symmetric(horizontal: 16), //Edits the size of the button box
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(2)),),);
    final ButtonStyle colored = ElevatedButton.styleFrom(foregroundColor: Colors.yellow,backgroundColor: Colors.purple);

    return Center(
      child: Column( //Column containing everything
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row( //Row containing the normal default elevated buttons
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
          ElevatedButton(style: style, onPressed: null, child: const Text('Disabled Button')),
          const SizedBox(width: 10), //
          ElevatedButton(style: style, onPressed: () {}, child: const Text('Enabled Button')),
            ]
            ),
          const SizedBox(height:10), //Vertical distance between the two types of buttons
          Row( //Row containing the raised buttons
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
          ElevatedButton(style: raised, onPressed: null, child: const Text('Disabled Raised Button')),
          const SizedBox(width: 10),
          ElevatedButton(style: raised, onPressed: () {}, child: const Text('Enabled Raised Button')),
            ]
            ),
          const SizedBox(height:10),
          Row( //Row containing the icon elevated buttons
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
          ElevatedButton(style: style, onPressed: null, child: const Icon(Icons.favorite,color: Colors.pink,size: 30.0)),
          const SizedBox(width: 10), //
          ElevatedButton(style: style, onPressed: () {}, child: const Icon(Icons.favorite,color: Colors.pink,size: 30.0)),
            ]
            ),
          const SizedBox(height:10),
          Row( //Row containing the colored default elevated buttons
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
          ElevatedButton(style: colored, onPressed: null, child: const Text('Disabled Colored Button')),
          const SizedBox(width: 10), //
          ElevatedButton(style: colored, onPressed: () {}, child: const Text('Enabled Colored Button')),
            ]
            ),
          const SizedBox(height:10),
          Row( //Row containing the debugging elevated buttons
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
          ElevatedButton(style: style, onPressed: null, onLongPress: () {debugPrint('Short Disabled Button has been long pressed');}, //short press disabled button
          child: const Text('Short Disabled Button')),
          const SizedBox(width: 10), //
          ElevatedButton(style: style, onPressed: () {debugPrint('Long Disabled Button has been pressed');}, onLongPress: null, //Long press disabled button (note:long press works on unclick)
          child: const Text('Long Disabled Button')), 
          const SizedBox(width:10),
          ElevatedButton(style: style, onPressed: () {debugPrint('Button has been short pressed');}, //fully enabled button
          onLongPress: () {debugPrint('Button has been long pressed');}, 
          child: const Text('Enabled Button')),
            ]
            ),
            const SizedBox(height:10),
          Slider( //Example slider that changes the other bars secondary bar
            value: _currentSliderSecondaryValue,
            label: _currentSliderSecondaryValue.round().toString(),
            onChanged: (double value) {
              setState(() {
                _currentSliderSecondaryValue = value;
              });
            },
          ),
          const SizedBox(height:10),
          Slider( //example slider with a secondary bar
            value: _currentSliderPrimaryValue,
            secondaryTrackValue: _currentSliderSecondaryValue,
            label: _currentSliderPrimaryValue.round().toString(),
            onChanged: (double value) {
              setState(() {
                _currentSliderPrimaryValue = value;
              });
            },
          ),
          Slider( //Volume bar 0-100 using only 10s place
            value:_sliderVolumeValue,
            label:(_sliderVolumeValue*100).round().toString(),
            divisions: 10,
            onChanged:(double value) {
              debugPrint('Current volume is:${(value*100).round()}');
              setState(() {
                _sliderVolumeValue = value;
              });
            }
          ),
          Slider( //Volume bar 0-100
            value:_sliderVolumeValue,
            label:(_sliderVolumeValue*100).round().toString(),
            divisions: 100,
            onChanged:(double value) {
              debugPrint('Current volume is:${(value*100).round()}');
              setState(() {
                _sliderVolumeValue = value;
              });
            }
          ),
           if (_sliderVolumeValue == 0) 
          const SizedBox(height: 10),
          if (_sliderVolumeValue == 0) 
          ElevatedButton(style: style, onPressed: null, child:
          const Icon(Icons.volume_off,
          color: Colors.black,size: 30.0)),
          const SizedBox(height: 10),
          if (_sliderVolumeValue != 0) 
          ElevatedButton(style: style, onPressed: null, child:
          const Icon(Icons.volume_up,
          color: Colors.black,size: 30.0)),
        ],
      ),
    );
  }
}