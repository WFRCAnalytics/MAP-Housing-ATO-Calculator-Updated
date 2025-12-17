var dCounties = [  // COUNTYNBR
  { label: "Weber    ", value: "29" },
  { label: "Davis    ", value: "06" },
  { label: "Salt Lake", value: "18" },
  { label: "Utah     ", value: "25" }
];

var sClickOnMapText = "<FONT COLOR=\"red\"><i>Click on one or more cities to start</i></FONT>";
var sClickOnMapToAddMoreText = "<br/><i>To remove city, click on name in list. To add another city, click on it in map.</i>";
var sSelectOptionAboveText = "<i>Select option above.</i>";

var aCommunityNames = [];

var dCommunities = [];

var sDistrictRGB = "rgba(102,102,229,0.6)"; //Blue color for to districts. Last value 'alpha' controls transparency.

var sClickConfirmation = "Use mouse to select district(s) on map. Do not click on district label. Click button when done.";

var dLandUseFilter = [
  { label: "All Land Uses", value: "'AG','EM','OS','CH','SF','MF','GQ','GO','ED','HE','RE','OF','IN','OT','UT','NB','NO'" },
  { label: "Residential", value: "'SF','MF'" }, // Single Family, Multi Family
  { label: "Commercial", value: "'HE','RE','OF','IN'"}//, // Heathcare, Retail, Office, Industrial
  //{ label: "Undeveloped", value: "'AG','NB'"} // Agriculture, No Building
];

var aCategories = ['CM', 'CU', 'CC', 'CN', 'AA', 'AT', 'TT', 'TF', 'TA', 'AC', 'AH', 'AE', 'AG', 'AM', 'AP'];
var aCategories_Names = ['Metropolitan Centers', 'Urban Centers', 'City Centers', 'Neighborhood Centers', 'Auto Access to Jobs', 'Transit Access to Jobs', 'Transit', 'Freeway Access', 'Active Transportation Facilities', 'Child Care', 'Health Care', 'Schools', 'Grocery', 'Community Centers', '10-Minute Walk to Parks'];
var aCategories_Groups = ['places', 'places', 'places', 'places', 'access', 'access', 'transp', 'transp', 'transp', 'necess', 'necess', 'necess', 'necess', 'necess', 'necess'];

var dDisplayDict = [
  ['CM', 'Metropolitan Centers', 'KeepScoresOn'],
  ['CU', 'Urban Centers', 'KeepScoresOn'],
  ['CC', 'City Centers', 'KeepScoresOn'],
  ['CN', 'Neighborhood Centers', 'KeepScoresOn'],
  ['AA', 'Accessible Jobs - Auto', 'KeepScoresOn'],
  ['AT', 'Accessible Jobs - Transit', 'KeepScoresOn'],
  ['TT', 'Local Bus Stops', 'KeepScoresOn'],
  ['TT', 'CRT Stops', 'KeepScoresOn'],
  ['TT', 'CRT Stops - Future', 'KeepScoresOn'],
  ['TT', 'LRT Stops', 'KeepScoresOn'],
  ['TT', 'LRT Stops - Future', 'KeepScoresOn'],
  ['TT', 'BRT Stops', 'KeepScoresOn'],
  ['TT', 'BRT Stops - Future', 'KeepScoresOn'],
  ['TF', 'Interchanges', 'KeepScoresOn'],
  ['TF', 'Interchanges - Future', 'KeepScoresOn'],
  ['TA', 'Active Transportation Paths', 'KeepScoresOn'],
  ['TA', 'Active Transportation Paths - Future', 'KeepScoresOn'],
  ['TA', 'Active Transportation Protected Bike Lanes', 'KeepScoresOn'],
  ['TA', 'Active Transportation Protected Bike Lanes - Future', 'KeepScoresOn'],
  ['AC', 'Child Care', 'KeepScoresOn'],
  ['AH', 'Health Care', 'KeepScoresOn'],
  ['AG', 'Grocery Stores', 'KeepScoresOn'],
  ['AE', 'K-12 Public Schools', 'KeepScoresOn'],
  ['AE', 'Higher Education', 'KeepScoresOn'],
  ['AM', 'Community Centers', 'KeepScoresOn'],
  ['AP', '10-Minute Walk to Parks', 'KeepScoresOn']
]

var aCategoryWeights = [];

// need some kind of container to save weights so that toggling between communities with or without the category, the value is saved somewhere....
// use aCategories as index array
var aCategoryWeights_Saved = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

var sCurCommunities = "";
var dCurCommunities = [];
var lyrCommunity;
var lyrCommunity_Selected;
var sCommunityLayer = 'Communities';
var sCommunityLayer_Selected = 'Communities-Selected';

var lyrParcelPieces;
var sParcelPiecesLayer = 'Housing ATO';

var curLandUseFilter = "'AG','EM','OS','CH','SF','MF','GQ','GO','ED','HE','RE','OF','IN','OT','UT','NB','NO'"

// which cities have utah qualified opportunity zones
var UtahQualOppZoneCities = "'OG','SO'"

var wH;
var maxScore_Places = 0.0;
var maxScore_Access = 0.0;
var maxScore_Transp = 0.0;
var maxScore_Necess = 0.0;
var maxPossible = 0.0;
var iPixelSelectionTolerance = 5;
var curParcelPieceUNIQID = 0;

var WIDGETPOOLID_LEGEND = 0;
var WIDGETPOOLID_SCORE = 2;

var bLocationGraphic = false;

var curCommSelMode = 'single';

var cmbCommunities_Single;
var cmbCommunities_Multi;
var cmbCounty;

var strSelectedPriorities = '';
var curSlideCM = 1.0;

var curSlideValues = {};


define(['dojo/_base/declare',
  'dojo/dom',
  'jimu/BaseWidget',
  'dijit/form/CheckBox',
  'dojo/html',
  'dojo/domReady!',
  'jimu/PanelManager',
  'esri/layers/FeatureLayer',
  'jimu/LayerInfos/LayerInfos',
  'dijit/form/Select',
  'dijit/form/Button',
  'dijit/form/ComboBox',
  'esri/tasks/query',
  'esri/tasks/QueryTask',
  'esri/geometry/Extent',
  'esri/renderers/UniqueValueRenderer',
  'esri/symbols/SimpleFillSymbol',
  'esri/symbols/SimpleLineSymbol',
  'esri/symbols/SimpleMarkerSymbol',
  'esri/Color',
  'jimu/PanelManager',
  'esri/graphic',
  'dojo/store/Memory',
  'dijit/form/HorizontalSlider',
  'dijit/registry'],
  function (declare, dom, BaseWidget, CheckBox, html, domReady, PanelManager, FeatureLayer, LayerInfos, Select, Button, ComboBox, Query, QueryTask, Extent, UniqueValueRenderer, SimpleFillSymbol, SimpleLineSymbol, SimpleMarkerSymbol, Color, PanelManager, Graphic, Memory, HorizontalSlider, registry) {
    //To create a widget, you need to derive from BaseWidget.
    return declare([BaseWidget], {
      // Custom widget code goes here

      baseClass: 'jimu-widget-customwidget',

      //this property is set by the framework when widget is loaded.
      //name: 'CustomWidget',


      //methods to communication with app container:

      // postCreate: function() {
      //   this.inherited(arguments);
      //   console.log('postCreate');
      // },

      startup: function () {
        this.inherited(arguments);
        //this.mapIdNode.innerHTML = 'map id:' + this.map.id;
        //console.log('startup');

        wH = this;
        this.map.setInfoWindowOnClick(false); // turn off info window (popup) when clicking a feature

        dom.byId('addText').innerHTML = sClickOnMapText;

        //Widen the widget panel to provide more space for charts
        var panel = this.getPanel();
        var pos = panel.position;
        //originalwidth = pos.width;
        pos.width = 450;
        panel.setPosition(pos);
        panel.panelManager.normalizePanel(panel);

        // Iterate over categories and create sliders
        aCategories.forEach(function(cat) {
          // initialize each slider's value (default 0.5, or use existing if needed)
          curSlideValues[cat] = curSlideValues[cat] || 0.5;

          // Create slider
          new HorizontalSlider(
            {
              minimum: 0,
              maximum: 1,
              discreteValues: 5,
              value: curSlideValues[cat],
              intermediateChanges: true,
              onChange: function () {
                curSlideValues[cat] = this.value;
                console.log("Slider " + cat + " changed → " + this.value);
                wH._updateDisplay();
              },
            },
            "horizslider" + cat // assumes you have divs with ids: horizsliderCM, horizsliderCU, etc.
          ).startup();
        });

        // Initialize Selection Layer, FromLayer, and ToLayer and define selection colors
        var layerInfosObject = LayerInfos.getInstanceSync();
        for (var j = 0, jl = layerInfosObject._layerInfos.length; j < jl; j++) {
          var currentLayerInfo = layerInfosObject._layerInfos[j];
          if (currentLayerInfo.title == sCommunityLayer) {
            lyrCommunity = layerInfosObject._layerInfos[j].layerObject;
            console.log(sCommunityLayer + ' Found');
          } else if (currentLayerInfo.title == sCommunityLayer_Selected) {
            lyrCommunity_Selected = layerInfosObject._layerInfos[j].layerObject;
            lyrCommunity_Selected.setDefinitionExpression("CommCode IN ('NONE')");
            lyrCommunity_Selected.show();
            console.log(sCommunityLayer_Selected + ' Found');
          } else if (currentLayerInfo.title == sParcelPiecesLayer) {
            lyrParcelPieces = layerInfosObject._layerInfos[j].layerObject;
            lyrParcelPieces.setDefinitionExpression("CommCode IN ('NONE')");
            lyrParcelPieces.show();
            console.log('Parcel Pieces Layer Found')
          }
        }


        // Populate classbreaks object - for forecast years
        dojo.xhrGet({
          url: "widgets/Housing/data/communities.json",
          handleAs: "json",
          load: function (obj) {
            /* here, obj will already be a JS object deserialized from the JSON response */
            console.log('communities.json');
            dCommunities = obj;
          },
          error: function (err) {
            /* this will execute if the response couldn't be converted to a JS object,
               or if the request was unsuccessful altogether. */
          }
        });

        // Map display zones
        var _cmbLandUseFilter = new Select({
          id: "selectLandUseFilter",
          name: "selectLandUseFilterName",
          options: dLandUseFilter,
          onChange: function () {
            curLandUseFilter = this.value;
            wH._updateDisplay();
          }
        }, "cmbLandUseFilter");
        _cmbLandUseFilter.startup();
        _cmbLandUseFilter.set("value", curLandUseFilter);

        // set change event for categories
        for (let i = 0; i < aCategories.length; i++) {
          console.log('Set onchange events for ' + aCategories[i])
          // check if 'rank' + XX exists
          var obj;
          if (isNaN(dom.byId('rank' + aCategories[i]))) {
            obj = dom.byId('rank' + aCategories[i])
          } else {
            obj = dom.byId('horizslider' + aCategories[i])
          }
          obj.onchange = function () {
            // updated saved for use when switching between communities that may not have values category, which would set the value to zer
            aCategoryWeights_Saved[i] = this.value;

            wH._updateDisplay();
            wH.publishData({
              message: curParcelPieceUNIQID
            });
          };
          dom.byId('chk' + aCategories[i]).onchange = function () {
            wH._turnOnOffLayers();
          };
        }
        dom.byId('opportunityzones').onchange = function () {
          wH._updateDisplay();
        };

        //setup click functionality
        this.map.on('click', selectParcelPiece);

        function pointToExtent(map, point, toleranceInPixel) {
          var pixelWidth = wH.map.extent.getWidth() / wH.map.width;
          var toleranceInMapCoords = toleranceInPixel * pixelWidth;
          return new Extent(point.x - toleranceInMapCoords,
            point.y - toleranceInMapCoords,
            point.x + toleranceInMapCoords,
            point.y + toleranceInMapCoords,
            wH.map.spatialReference);
        }

        //Setup function for selecting communities and parcels

        function selectParcelPiece(evt) {
          console.log('selectParcelPiece');

          var query = new Query();
          query.geometry = pointToExtent(wH.map, evt.mapPoint, iPixelSelectionTolerance);
          query.returnGeometry = false;
          query.outFields = ["*"];

          var queryCommunity = new QueryTask(lyrCommunity.url);
          queryCommunity.execute(query, clickCommunity);

          //Segment search results
          function clickCommunity(results) {
            console.log('clickCommunity');

            var resultCount = results.features.length;
            if (resultCount > 0) {
              var _communityCode = results.features[0].attributes['CommCode'];

              // if community is not already selected, add it to the list
              if (dCurCommunities.indexOf(_communityCode) == -1) {
                var _communitiesText = dom.byId('communitiesText');

                var _communityName = dCommunities.find(item => item.value == _communityCode).label;
                dCurCommunities.push(_communityCode);
                sCurCommunities = "'" + dCurCommunities.join("','") + "'";

                //change selection
                lyrCommunity_Selected.setDefinitionExpression('CommCode IN (' + sCurCommunities + ')')
                lyrCommunity.setDefinitionExpression('CommCode NOT IN (' + sCurCommunities + ')')

                wH._afterChangeCommunity();

                // after
                dojo.place("<div class = \"community\" id=\"comm_" + _communityCode + "\">" + _communityName + "</div>", "communitiesText");

                dom.byId("comm_" + _communityCode).onclick = function (evt) {
                  console.log('Remove ' + _communityCode);

                  dojo.destroy("comm_" + _communityCode);

                  const index = dCurCommunities.indexOf(_communityCode);
                  if (index > -1) { // only splice array when item is found
                    dCurCommunities.splice(index, 1); // 2nd parameter means remove one item only
                  }
                  sCurCommunities = "'" + dCurCommunities.join("','") + "'";

                  if (dCurCommunities.length == 0) {
                    dom.byId('addText').innerHTML = sClickOnMapText;
                  }

                  //change selection
                  lyrCommunity_Selected.setDefinitionExpression('CommCode IN (' + sCurCommunities + ')')
                  lyrCommunity.setDefinitionExpression('CommCode NOT IN (' + sCurCommunities + ')')
                  wH._afterChangeCommunity();

                };

                dom.byId('addText').innerHTML = sClickOnMapToAddMoreText;

              // if community is already selected, query the parcel layer and show score
              } else {
                var queryParcelPiece = new QueryTask(lyrParcelPieces.url);
                queryParcelPiece.execute(query, clickParcelPiece);

                //Segment search results
                function clickParcelPiece(results) {
                  console.log('clickParcelPiece');

                  var resultCount = results.features.length;
                  if (resultCount > 0) {
                    //use first feature only
                    var featureAttributes = results.features[0].attributes;
                    curParcelPieceUNIQID = featureAttributes['OBJECTID'];

                    var symbol = new SimpleMarkerSymbol().setSize(15).setColor(new Color("#6b39fd"));

                    var graphic = new Graphic(evt.mapPoint);

                    graphic.setSymbol(symbol);
                    //graphic.geometry = evt.mapPoint;
                    //graphic.setInfoTemplate(popupTemplate);
                    if (bLocationGraphic) {
                      // should only be one graphic in addition to communities at a time (community borders and selection)
                      // so remove the last
                      //wH.map.graphics.remove(wH.map.graphics.graphics[wH.map.graphics.graphics.length-1]);
                      wH.map.graphics.clear();
                      bLocationGraphic = false;
                    }
                    wH.map.graphics.add(graphic);
                    bLocationGraphic = true;

                    // Open scoring widget
                    var pm = PanelManager.getInstance();

                    //Close Segment Widget if open
                    //for (var p=0; p < pm.panels.length; p++) {
                    //    if (pm.panels[p].label == sSegWidgetLabel) {
                    //        pm.closePanel(pm.panels[p]);
                    //      }
                    //}

                    //Open scoring widget
                    pm.showPanel(wH.appConfig.widgetPool.widgets[WIDGETPOOLID_SCORE]);

                    wH.publishData({
                      message: curParcelPieceUNIQID
                    });
                  }
                }
              }
            }
          }
        }
      },

      _showLegend: function () {
        var pm = PanelManager.getInstance();
        pm.showPanel(wH.appConfig.widgetPool.widgets[WIDGETPOOLID_LEGEND]);
        //Close Location Scores if open
        var pm = PanelManager.getInstance();
        for (var p = 0; p < pm.panels.length; p++) {
          if (pm.panels[p].label == 'Location Scores') {
            pm.closePanel(pm.panels[p]);
          }
        }
      },

      _afterChangeCommunity: function () {
        console.log('_afterChangeCommunity');
        // after sCurCommunities updated
        if (sCurCommunities == "''" || sCurCommunities == "'__'") {

          //Close Location Scores if open
          var pm = PanelManager.getInstance();
          for (var p = 0; p < pm.panels.length; p++) {
            if (pm.panels[p].label == 'Legend') {
              pm.closePanel(pm.panels[p]);
            }
          }

        }

        wH._updateOppZoneDisplay();

        if (sCurCommunities != "") {
          wH._zoomToCommunity();
          wH._checkCommunityNAs();
        }
        wH._updateDisplay();
        wH._turnOnOffLayers();

        //Close Location Scores if open
        var pm = PanelManager.getInstance();
        for (var p = 0; p < pm.panels.length; p++) {
          if (pm.panels[p].label == 'Location Score') {
            pm.closePanel(pm.panels[p]);
          }
        }
      },

      _checkCommunityNAs: function () {
        // check what centers are in a community and update user interface as appropriate
        for (i = 0; i < aCategories.length; i++) {

          // initialize as hidden
          dom.byId('row' + aCategories[i]).style.display = 'none';
          dom.byId('none' + aCategories[i]).style.display = 'table-row';
          if (isNaN(dom.byId('rank' + aCategories[i]))) {
            priorityWidget = dom.byId('rank' + aCategories[i]);
          } else {
            priorityWidget = dom.byId('horizslider' + aCategories[i]);
          }
          priorityWidget.value = '0.0000';
          dom.byId('chk' + aCategories[i]).checked = false;

          // check if communities have categories
          for (j = 0; j < dCurCommunities.length; j++) {
            _catsincommunity = dCommunities.find(item => item.value == dCurCommunities[j]).categories
            if (_catsincommunity.includes(aCategories[i])) {
              dom.byId('row' + aCategories[i]).style.display = 'table-row';
              dom.byId('none' + aCategories[i]).style.display = 'none';
              //use saved value, which is last manually selected by user
              priorityWidget.value = aCategoryWeights_Saved[i];
              // break out if one community has score available
              break;
            }
          }
        }

      },

      _updateDisplay: function () {
        console.log('_updateDisplay');

        // filter by Community Code and Building Code
        _strFilterExpression = "CommCode IN (" + sCurCommunities + ") AND BC IN (" + curLandUseFilter + ")"

        // add opportunity zone filter
        if (dom.byId('opportunityzones').value == 'Y') {
          _strFilterExpression = _strFilterExpression + " AND OZ=1"
        }
        lyrParcelPieces.setDefinitionExpression(_strFilterExpression);

        // build expression for symbology based on each categories rank
        var _scoreExp = '';
        var _strHig = '';
        var _strMed = '';
        var _strLow = '';
        var _strSlide = '';

        maxScore_Places = 0.0;
        maxScore_Access = 0.0;
        maxScore_Transp = 0.0;
        maxScore_Necess = 0.0;

        maxPossible = 0.0;

        aCategoryWeights = [];

        for (let i = 0; i < aCategories.length; i++) {
          // get value from select
          var _catSelect = dom.byId('rank' + aCategories[i])
          if (isNaN(_catSelect)) {
            _value = parseFloat(_catSelect.value);
          } else {
            // if no select, get value from slider
            _value = curSlideValues[aCategories[i]];
          }
          _scoreExp += " $feature." + aCategories[i] + " * " + String(_value)

          aCategoryWeights.push(_value);

          switch (aCategories_Groups[i]) {
            case 'places':
              if (_value > maxScore_Places) { // can't add max since these places never overlap
                maxScore_Places = _value;
              }
              break;
            case 'access':
              maxScore_Access += _value;
              break;
            case 'transp':
              maxScore_Transp += _value;
              break;
            case 'necess':
              maxScore_Necess += _value;
              break;
          }

          // for all but last item add plus(+) sign between expressions
          if (i != aCategories.length - 1) {
            _scoreExp += " + ";
          }

          if (isNaN(_catSelect)) {
            switch (dom.byId('rank' + aCategories[i]).value) {
              case '0.3333':
                _strLow += aCategories_Names[i] + ", ";
                break;
              case '0.6667':
                _strMed += aCategories_Names[i] + ", ";
                break;
              case '1.0000':
                _strHig += aCategories_Names[i] + ", ";
                break;
            }
          } else {
            // build string description of category and weight
            _strSlide += aCategories_Names[i] + ": " + dom.byId('horizslider' + aCategories[i]).value  + ", ";
          }
        }

        maxPossible = maxScore_Places + maxScore_Access + maxScore_Transp + maxScore_Necess;

        if (_strHig.length > 0 && _strMed.length > 0 && _strLow.length > 0) {
          strSelectedPriorities = 'High Priority: ' + _strHig.substring(0, _strHig.length - 2) + " -- " + 'Medium Priority: ' + _strMed.substring(0, _strMed.length - 2) + " -- " + 'Low Priority: ' + _strLow.substring(0, _strLow.length - 2);
        } else if (_strHig.length > 0 && _strMed.length > 0 && _strLow.length == 0) {
          strSelectedPriorities = 'High Priority: ' + _strHig.substring(0, _strHig.length - 2) + " -- " + 'Medium Priority: ' + _strMed.substring(0, _strMed.length - 2);
        } else if (_strHig.length > 0 && _strMed.length == 0 && _strLow.length > 0) {
          strSelectedPriorities = 'High Priority: ' + _strHig.substring(0, _strHig.length - 2) + " -- " + 'Low Priority: ' + _strLow.substring(0, _strLow.length - 2);
        } else if (_strHig.length == 0 && _strMed.length > 0 && _strLow.length > 0) {
          strSelectedPriorities = 'Medium Priority: ' + _strMed.substring(0, _strMed.length - 2) + " -- " + 'Low Priority: ' + _strLow.substring(0, _strLow.length - 2);
        } else if (_strHig.length > 0 && _strMed.length == 0 && _strLow.length == 0) {
          strSelectedPriorities = 'High Priority: ' + _strHig.substring(0, _strHig.length - 2);
        } else if (_strHig.length > 0 && _strMed.length == 0 && _strLow.length == 0) {
          strSelectedPriorities = 'Medium Priority: ' + _strMed.substring(0, _strMed.length - 2);
        } else if (_strHig.length == 0 && _strMed.length == 0 && _strLow.length > 0) {
          strSelectedPriorities = 'Low Priority: ' + _strLow.substring(0, _strLow.length - 2);
        } else {
          strSelectedPriorities = '';
        }

        if (_strSlide.length > 0) {
          strSelectedPriorities += "  Weights: " + _strSlide.substring(0, _strSlide.length - 2);
        }

        var vcUVRenderer = new UniqueValueRenderer({
          type: "unique-value",  // autocasts as new UniqueValueRenderer()
          valueExpression: "" +
            "var score = (" + _scoreExp + ')/' + maxPossible + ";" +
            "if      (score>0.80) { return 'class_5'; }" +
            "else if (score>0.60) { return 'class_4'; }" +
            "else if (score>0.40) { return 'class_3'; }" +
            "else if (score>0.20) { return 'class_2'; }" +
            "else                 { return 'class_1'; }",
          uniqueValueInfos: [
            { value: "class_5", label: "Most Accessibility (80-100% of Max Possible)", symbol: new SimpleFillSymbol(SimpleFillSymbol.STYLE_SOLID, new SimpleLineSymbol(SimpleLineSymbol.STYLE_NULL, new Color([255, 255, 255]), 5), new Color("#031273")) },
            { value: "class_4", label: "High Accessibility (60-80% of Max Possible)", symbol: new SimpleFillSymbol(SimpleFillSymbol.STYLE_SOLID, new SimpleLineSymbol(SimpleLineSymbol.STYLE_NULL, new Color([255, 255, 255]), 5), new Color("#2c7fb8")) },
            { value: "class_3", label: "Middle Accessibility (40-60% of Max Possible)", symbol: new SimpleFillSymbol(SimpleFillSymbol.STYLE_SOLID, new SimpleLineSymbol(SimpleLineSymbol.STYLE_NULL, new Color([255, 255, 255]), 5), new Color("#52c7d5")) },
            { value: "class_2", label: "Low Accessibility (20-40% of Max Possible)", symbol: new SimpleFillSymbol(SimpleFillSymbol.STYLE_SOLID, new SimpleLineSymbol(SimpleLineSymbol.STYLE_NULL, new Color([255, 255, 255]), 5), new Color("#a1dab4")) },
            { value: "class_1", label: "Least Accessibility (0-20% of Max Possible)", symbol: new SimpleFillSymbol(SimpleFillSymbol.STYLE_SOLID, new SimpleLineSymbol(SimpleLineSymbol.STYLE_NULL, new Color([255, 255, 255]), 5), new Color("#ffffcc")) }
          ]

        });
        lyrParcelPieces.setRenderer(vcUVRenderer);

        //        wH._createChart(_strFilterExpression, _scoreExp);


        // Update Location Score if open
        var pm = PanelManager.getInstance();
        for (var p = 0; p < pm.panels.length; p++) {
          if (pm.panels[p].label == 'Location Score') {
            wH.publishData({
              message: curParcelPieceUNIQID
            });
          }
        }


      },

      //    _createChart: function(_strFilterExpression, _scoreExp) {
      //        console.log('_createChart');
      //
      //        var query = new Query();
      //        query.returnGeometry = false;
      //        query.outFields = ["*"];
      //        query.where = _strFilterExpression;
      //
      //        var queryParcelPiece = new QueryTask(lyrParcelPieces.url);
      //        queryParcelPiece.execute(query,getAreasByClass);
      //
      //        //Segment search results
      //        function getAreasByClass(results) {
      //            console.log('getAreasByClass');
      //
      //            _area_class5 = 0;
      //            _area_class4 = 0;
      //            _area_class3 = 0;
      //            _area_class2 = 0;
      //            _area_class1 = 0;
      //
      //            var resultCount = results.features.length;
      //            if (resultCount>0) {
      //                //use first feature only
      //                for (i=0;i<resultCount;i++) {
      //                    var featureAttributes = results.features[0].attributes;
      //
      //                    _score = (featureAttributes[aCategories[00]] * aCategoryWeights[00]) +
      //                             (featureAttributes[aCategories[01]] * aCategoryWeights[01]) +
      //                             (featureAttributes[aCategories[02]] * aCategoryWeights[02]) +
      //                             (featureAttributes[aCategories[03]] * aCategoryWeights[03]) +
      //                             (featureAttributes[aCategories[04]] * aCategoryWeights[04]) +
      //                             (featureAttributes[aCategories[05]] * aCategoryWeights[05]) +
      //                             (featureAttributes[aCategories[06]] * aCategoryWeights[06]) +
      //                             (featureAttributes[aCategories[07]] * aCategoryWeights[07]) +
      //                             (featureAttributes[aCategories[08]] * aCategoryWeights[08]) +
      //                             (featureAttributes[aCategories[09]] * aCategoryWeights[09]) +
      //                             (featureAttributes[aCategories[10]] * aCategoryWeights[10]) +
      //                             (featureAttributes[aCategories[11]] * aCategoryWeights[11]) +
      //                             (featureAttributes[aCategories[12]] * aCategoryWeights[12]) +
      //                             (featureAttributes[aCategories[13]] * aCategoryWeights[13]) +
      //                             (featureAttributes[aCategories[14]] * aCategoryWeights[14]) ;
      //
      //                    if        (_score>maxPossible*0.80) {
      //                        _area_class5 += featureAttributes['Shape__Area'];
      //                    } else if (_score>maxPossible*0.60) {
      //                        _area_class4 += featureAttributes['Shape__Area'];
      //                    } else if (_score>maxPossible*0.40) {
      //                        _area_class3 += featureAttributes['Shape__Area'];
      //                    } else if (_score>maxPossible*0.20) {
      //                        _area_class2 += featureAttributes['Shape__Area'];
      //                    } else                               {
      //                        _area_class1 += featureAttributes['Shape__Area'];
      //                    }
      //                }
      //            }
      //            console.log('class5area: ' + String(_area_class5));
      //            console.log('class4area: ' + String(_area_class4));
      //            console.log('class3area: ' + String(_area_class3));
      //            console.log('class2area: ' + String(_area_class2));
      //            console.log('class1area: ' + String(_area_class1));
      //        }
      //    },

      _updateOppZoneDisplay: function () {
        console.log('_updateOppZoneDisplay');
        for (i = 0; i < dCurCommunities.length; i++) {
          if (dCommunities.find(item => item.value == dCurCommunities[i]).oppzones == 'yes') {
            dom.byId("oppzones").style.display = 'block';
            break;
          } else {
            dom.byId("oppzones").style.display = 'none';
          }

        }
      },

      _turnOnOffLayers: function () {
        console.log('_turnOnOffLayers')
        // turn on/off data layers

        var _bTurnScoresOff = false;

        // loop through all layers in map
        var layerInfosObject = LayerInfos.getInstanceSync();
        for (var j = 0, jl = layerInfosObject._layerInfos.length; j < jl; j++) {
          var _curLayerInfo = layerInfosObject._layerInfos[j];
          var _curLayerTitle = _curLayerInfo.title;

          // loop through display dictionary and check against layer name
          for (var k = 0; k < dDisplayDict.length; k++) {

            // if dictionary item equals current category
            if (dDisplayDict[k][1] == _curLayerTitle) {

              // check if item checked
              if (dom.byId('chk' + dDisplayDict[k][0]).checked == true) {
                _curLayerInfo.layerObject.show()
                if (dDisplayDict[k][2] == 'TurnScoresOff') {
                  _bTurnScoresOff = true;
                }
              } else {
                _curLayerInfo.layerObject.hide()
              }
            }
          }
        }
        //if (_bTurnScoresOff==true) {
        //    lyrParcelPieces.hide();
        //} else {
        //    lyrParcelPieces.show();
        //}
        //if (sCurCommunities=="''" || sCurCommunities=="'__'") {
        //    lyrCommunity.show();
        //} else {
        //    lyrCommunity.hide();
        //}
      },

      _expandCenters: function () {
        console.log('_expandCenters');
        if (dom.byId("divCentersExpand").innerHTML == 'Collapse') {
          dom.byId("centerschoices").style.display = 'none';
          dom.byId("divCentersExpand").innerHTML = 'Expand';
        } else {
          dom.byId("centerschoices").style.display = 'block';
          dom.byId("divCentersExpand").innerHTML = 'Collapse';
        }
      },



      _expandATO: function () {
        console.log('_expandATO');
        if (dom.byId("divATOExpand").innerHTML == 'Collapse') {
          dom.byId("atochoices").style.display = 'none';
          dom.byId("divATOExpand").innerHTML = 'Expand';
        } else {
          dom.byId("atochoices").style.display = 'block';
          dom.byId("divATOExpand").innerHTML = 'Collapse';
        }
      },

      _expandTransportation: function () {
        console.log('_expandTransportation');
        if (dom.byId("divTransportationExpand").innerHTML == 'Collapse') {
          dom.byId("transportationchoices").style.display = 'none';
          dom.byId("divTransportationExpand").innerHTML = 'Expand';
        } else {
          dom.byId("transportationchoices").style.display = 'block';
          dom.byId("divTransportationExpand").innerHTML = 'Collapse';
        }
      },

      _expandAmenities: function () {
        console.log('_expandAmenities');
        if (dom.byId("divAmenitiesExpand").innerHTML == 'Collapse') {
          dom.byId("amenitieschoices").style.display = 'none';
          dom.byId("divAmenitiesExpand").innerHTML = 'Expand';
        } else {
          dom.byId("amenitieschoices").style.display = 'block';
          dom.byId("divAmenitiesExpand").innerHTML = 'Collapse';
        }
      },

      _zoomToCommunity: function () {
        console.log('_zoomToCommunity');

        queryTask = new esri.tasks.QueryTask(lyrCommunity.url);

        query = new esri.tasks.Query();
        query.returnGeometry = true;
        query.outFields = ["*"];
        //query.where = "CommCode IN (" + sCurCommunities + ") AND COUNTYNBR='" + curCountyNumber + "'"; // ONLY SETUP FOR WASATCH FRONT AREA
        query.where = "CommCode IN (" + sCurCommunities + ")"; // ONLY SETUP FOR WASATCH FRONT AREA

        queryTask.execute(query, showResults);

        function showResults(featureSet) {

          var feature, featureId;

          // QueryTask returns a featureSet.  Loop through features in the featureSet and add them to the map.
          if (featureSet.features.length > 0) {
            if (featureSet.features[0].geometry.type == "polyline" || featureSet.features[0].geometry.type == "polygon") {
              // clearing any graphics if present.
              wH.map.graphics.clear();
              newExtent = new Extent(featureSet.features[0].geometry.getExtent())
              for (i = 0; i < featureSet.features.length; i++) {
                var graphic = featureSet.features[i];
                var thisExtent = graphic.geometry.getExtent();

                // making a union of extent or previous feature and current feature.
                newExtent = newExtent.union(thisExtent);
                //var _sfs = new SimpleFillSymbol(SimpleFillSymbol.STYLE_NULL,
                //    new SimpleLineSymbol(SimpleLineSymbol.STYLE_SOLID,
                //    new Color("#6b39fd"), 5),new Color([0,0,0,0])
                //);
                //graphic.setSymbol(_sfs);
                //graphic.setInfoTemplate(popupTemplate);
                //wH.map.graphics.add(graphic);
              }


              if (dom.byId("chkAutoZoom").checked == true) {
                //if (dom.byId("chkAutoPan").checked == true) {
                // zoom to new extent
                wH.map.setExtent(newExtent.expand(1.5));
                // pan to center of TAZ
                //wH.map.centerAt(newExtent.getCenter()); //recenters the map based on a map coordinate.
                //}
              }
            }
          }
        }
      },

      //Run when receiving a message
      onReceiveData: function (name, widgetId, data, historyData) {
        //filter out messages
        if (name == 'Location Score') {
          if (data.message == 'remove_location') {
            if (bLocationGraphic) {
              // should only be one graphic in addition to communities at a time (community borders and selection)
              // so remove the last
              wH.map.graphics.remove(wH.map.graphics.graphics[wH.map.graphics.graphics.length - 1]);
              bLocationGraphic = false;
            }
          }
          return;
        }
      },

      _turnoffall: function () {
        for (let i = 0; i < aCategories.length; i++) {
          var slider = registry.byId("horizslider" + aCategories[i]);
          if (slider) {
            slider.set("value", 0.0); // use .set() rather than direct assignment
          }
          aCategoryWeights_Saved[i] = 0;
        }
        wH._updateDisplay();
      }

      // onOpen: function(){
      //   console.log('onOpen');
      // },

      // onClose: function(){
      //   console.log('onClose');
      // },

      // onMinimize: function(){
      //   console.log('onMinimize');
      // },

      // onMaximize: function(){
      //   console.log('onMaximize');
      // },

      // onSignIn: function(credential){
      //   /* jshint unused:false*/
      //   console.log('onSignIn');
      // },

      // onSignOut: function(){
      //   console.log('onSignOut');
      // }

      // onPositionChange: function(){
      //   console.log('onPositionChange');
      // },

      // resize: function(){
      //   console.log('resize');
      // }
    });
  });
