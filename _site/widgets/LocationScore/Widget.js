define([
  'dojo/_base/declare',
  'dojo/dom',
  'dojo/dom-construct',
  'jimu/BaseWidget',
  'dijit/form/CheckBox',
  'dojo/html',
  'dojo/domReady!',
  'jimu/LayerInfos/LayerInfos',
  'dijit/form/Select',
  'esri/tasks/query',
  'esri/tasks/QueryTask',
  // charting
  'dojox/charting/Chart',
  'dojox/charting/plot2d/Columns',
  'dojox/charting/themes/Claro',
  'dojox/charting/axis2d/Default',
  'dojox/charting/action2d/Tooltip',
  'dojox/charting/action2d/Highlight',
  'dojox/charting/widget/Legend',
  'dojo/on'
], function(
  declare,
  dom,
  domConstruct,
  BaseWidget,
  CheckBox,
  html,
  domReady,
  LayerInfos,
  Select,
  Query,
  QueryTask,
  Chart,
  ColumnsPlot,
  themeClaro,
  DefaultAxis,
  Tooltip,
  Highlight,
  Legend,
  on
) {
  return declare([BaseWidget], {
    baseClass: 'jimu-widget-customwidget',

    startup: function() {
      this.inherited(arguments);
      wLS = this;

      this._chart = null;
      this._detailsShown = false; // tables hidden by default

      this.map.setInfoWindowOnClick(false);

      // Wire the toggle button if present
      var btn = dom.byId('detailsToggle');
      if (btn) {
        on(btn, 'click', function() { wLS._toggleDetails(); });
        // Ensure initial label/state
        wLS._applyDetailsVisibility();
      }

      wLS._updateScores();
    },

    _toggleDetails: function() {
      this._detailsShown = !this._detailsShown;
      this._applyDetailsVisibility();
    },

    _applyDetailsVisibility: function() {
      var btn = dom.byId('detailsToggle');
      var wrap = dom.byId('detailsTables'); // preferred wrapper
      var top = dom.byId('scoreTableTop');
      var bottom = dom.byId('scoreTableBottom');

      // If wrapper exists, just toggle it; else toggle both tables
      if (wrap) {
        wrap.style.display = this._detailsShown ? '' : 'none';
      } else {
        if (top) top.style.display = this._detailsShown ? '' : 'none';
        if (bottom) bottom.style.display = this._detailsShown ? '' : 'none';
      }

      // Button label & a11y
      if (btn) {
        btn.textContent = this._detailsShown ? 'Hide details' : 'See details';
        btn.setAttribute('aria-expanded', this._detailsShown ? 'true' : 'false');
      }
    },

    _updateScores: function() {
      console.log('_updateScores');

      var query = new Query();
      query.where = 'OBJECTID = ' + curParcelPieceUNIQID;
      query.returnGeometry = false;
      query.outFields = ['*'];

      var tblqueryTaskArea = new QueryTask(lyrParcelPieces.url);
      tblqueryTaskArea.execute(query, showParcelPieceResults);

      var self = this;

      function clearUI(msg) {
        // Destroy chart & legend
        if (self._chart) { self._chart.destroy(); self._chart = null; }
        if (self._legend) { self._legend.destroyRecursive(); self._legend = null; }
        // Clear tables and optionally show a one-line message in the top table
        var top = dom.byId('scoreTableTop');
        var bottom = dom.byId('scoreTableBottom');
        if (top) top.innerHTML = msg ? ('<tr><td>' + msg + '</td></tr>') : '';
        if (bottom) bottom.innerHTML = '';
        var titleNode = dom.byId('scoreChartTitle');
        if (titleNode) titleNode.textContent = '';
        var btn = dom.byId('detailsToggle');
        if (btn) btn.style.display = 'none';
        // Also hide the details area to avoid a blank block
        this._detailsShown = false;
        this._applyDetailsVisibility();
      }

      function showParcelPieceResults(results) {
        console.log('showParcelPieceResults');

        var topTbl = dom.byId('scoreTableTop');
        var bottomTbl = dom.byId('scoreTableBottom');

        if (!topTbl || !bottomTbl || !dom.byId('scoreChart')) {
          console.warn('Required HTML nodes are missing.');
          return;
        }

        var resultCount = results.features.length;
        if (resultCount <= 0) {
          clearUI('No location selected.');
          return;
        }

        // use first feature only
        var featureAttributes = results.features[0].attributes;

        if (!dCurCommunities.includes(featureAttributes['CommCode'])) {
          clearUI('Location is outside of selected communities.');
          return;
        }

        // ---------- compute tables + chart data ----------
        var topHtml = '';
        var bottomHtml = '';

        // Top: header
        topHtml += '<tr>' +
          '<td><strong>Layer</strong></td>' +
          '<td align="right"><strong>Score</strong></td>' +
          '<td align="right"><strong>Priority</strong><br/><strong>Weight</strong></td>' +
          '<td align="right"><strong>Weighted</strong></br><strong>Score</strong></td>' +
          '</tr>';

        var _totalweightedscore = 0;
        var _totalweightedscore_places = 0;
        var _totalweightedscore_access = 0;
        var _totalweightedscore_transp = 0;
        var _totalweightedscore_necess = 0;

        var _communitymaxpossible         = maxPossible      * 10;
        var _communitymaxpossible_places  = maxScore_Places  * 10;
        var _communitymaxpossible_access  = maxScore_Access  * 10;
        var _communitymaxpossible_transp  = maxScore_Transp  * 10;
        var _communitymaxpossible_necess  = maxScore_Necess  * 10;

        for (var i = 0; i < aCategoryWeights.length; i++) {
          var _shadetext = (i % 2 === 0) ? ' style="background-color:#DDDDDD"' : '';
          var _score = featureAttributes[aCategories[i]] * 10;
          var _weight = aCategoryWeights[i];
          var _weightedscore = _score * _weight;

          _totalweightedscore += _weightedscore;

          switch (aCategories_Groups[i]) {
            case 'places':
              _totalweightedscore_places += _weightedscore;
              break;
            case 'access':
              _totalweightedscore_access += _weightedscore;
              break;
            case 'transp':
              _totalweightedscore_transp += _weightedscore;
              break;
            case 'necess':
              _totalweightedscore_necess += _weightedscore;
              break;
          }

          topHtml += '<tr' + _shadetext + '>' +
            '<td>' + aCategories_Names[i] + '</td>' +
            '<td align="right">' + ((_score.toFixed(1) !== '0.0') ? _score.toFixed(1) : '0') + '</td>' +
            '<td align="right">' + ((_weight.toFixed(1) !== '0.0') ? _weight.toFixed(2) : 'n/a') + '</td>' +
            '<td align="right">' + ((_weightedscore.toFixed(1) !== '0.0') ? _weightedscore.toFixed(1) : '0') + '</td>' +
            '</tr>';
        }

        // Top: total row
        topHtml += '<tr>' +
          '<td><strong>Total</strong></td>' +
          '<td align="right"></td>' +
          '<td align="right"></td>' +
          '<td align="right"><strong>' + _totalweightedscore.toFixed(1) + '</strong></td>' +
          '</tr>';

        // Bottom: header row
        bottomHtml += '<tr>' +
          '<td><strong>&nbsp;</strong></td>' +
          '<td align="right"><strong>Places</strong></td>' +
          '<td align="right"><strong>Employ.</strong></td>' +
          '<td align="right"><strong>Transp.</strong></td>' +
          '<td align="right"><strong>Necess.</strong></td>' +
          '<td align="right"><strong>Total  </strong></td>' +
          '</tr>';

        var strCommunityText;
        if (dCurCommunities.length === 1) {
          strCommunityText = dCommunities.find(function(item) { return item.value === dCurCommunities[0]; }).label;
        } else {
          strCommunityText = 'Selected Communities';
        }

        // Bottom: totals
        bottomHtml += '<tr style="background-color:#DDDDDD">' +
          '<td><strong>Total Score for Selected Location</strong></td>' +
          '<td align="right">' + _totalweightedscore_places.toFixed(1) + '</td>' +
          '<td align="right">' + _totalweightedscore_access.toFixed(1) + '</td>' +
          '<td align="right">' + _totalweightedscore_transp.toFixed(1) + '</td>' +
          '<td align="right">' + _totalweightedscore_necess.toFixed(1) + '</td>' +
          '<td align="right"><strong>' + _totalweightedscore.toFixed(1) + '</strong></td>' +
          '</tr>';

        // Bottom: max possible
        bottomHtml += '<tr>' +
          '<td><strong>Max Possible for ' + strCommunityText + '</strong></td>' +
          '<td align="right">' + _communitymaxpossible_places.toFixed(1) + '</td>' +
          '<td align="right">' + _communitymaxpossible_access.toFixed(1) + '</td>' +
          '<td align="right">' + _communitymaxpossible_transp.toFixed(1) + '</td>' +
          '<td align="right">' + _communitymaxpossible_necess.toFixed(1) + '</td>' +
          '<td align="right"><strong>' + _communitymaxpossible.toFixed(1) + '</strong></td>' +
          '</tr>';

        // Bottom: percentages
        var pct_places = _communitymaxpossible_places ? (_totalweightedscore_places / _communitymaxpossible_places * 100) : 0;
        var pct_access = _communitymaxpossible_access ? (_totalweightedscore_access / _communitymaxpossible_access * 100) : 0;
        var pct_transp = _communitymaxpossible_transp ? (_totalweightedscore_transp / _communitymaxpossible_transp * 100) : 0;
        var pct_necess = _communitymaxpossible_necess ? (_totalweightedscore_necess / _communitymaxpossible_necess * 100) : 0;
        var pct_total  = _communitymaxpossible         ? (_totalweightedscore         / _communitymaxpossible         * 100) : 0;

        bottomHtml += '<tr style="background-color:#DDDDDD">' +
          '<td><strong>Percent of Max Possible</strong></td>' +
          '<td align="right">' + pct_places.toFixed(0) + '%</td>' +
          '<td align="right">' + pct_access.toFixed(0) + '%</td>' +
          '<td align="right">' + pct_transp.toFixed(0) + '%</td>' +
          '<td align="right">' + pct_necess.toFixed(0) + '%</td>' +
          '<td align="right"><strong>' + pct_total.toFixed(0) + '%</strong></td>' +
          '</tr>';

        // ---------- render UI ----------
        topTbl.innerHTML = topHtml;
        bottomTbl.innerHTML = bottomHtml;

        // Ensure the toggle & visibility are consistent after new data is written
        wLS._applyDetailsVisibility();

        // Optionally show the toggle button only when we have data
        var btn = dom.byId('detailsToggle');
        if (btn) btn.style.display = 'inline-block';

        // --- build chart data with PERCENT values; y-axis will be 0..100 ---
        var chartData = [
          { label: 'Places',
            y: +pct_places.toFixed(0),
            tooltip: pct_places.toFixed(0) + '% (' + _totalweightedscore_places.toFixed(1) + ' of ' + _communitymaxpossible_places.toFixed(1) + ')' },
          { label: 'Employ.',
            y: +pct_access.toFixed(0),
            tooltip: pct_access.toFixed(0) + '% (' + _totalweightedscore_access.toFixed(1) + ' of ' + _communitymaxpossible_access.toFixed(1) + ')' },
          { label: 'Transp.',
            y: +pct_transp.toFixed(0),
            tooltip: pct_transp.toFixed(0) + '% (' + _totalweightedscore_transp.toFixed(1) + ' of ' + _communitymaxpossible_transp.toFixed(1) + ')' },
          { label: 'Necess.',
            y: +pct_necess.toFixed(0),
            tooltip: pct_necess.toFixed(0) + '% (' + _totalweightedscore_necess.toFixed(1) + ' of ' + _communitymaxpossible_necess.toFixed(1) + ')' },
          { label: 'Total',
            y: +pct_total.toFixed(0),
            tooltip: pct_total.toFixed(0) + '% (' + _totalweightedscore.toFixed(1) + ' of ' + _communitymaxpossible.toFixed(1) + ')' }
        ];

        // Title can be static or dynamic; here’s a sensible default:
        wLS._setChartTitle('Weighted Score by Category');

        wLS._renderChart(chartData);
      }
    },

    _setChartTitle: function(text) {
      var chartNode = dom.byId('scoreChart');
      if (!chartNode) return;

      var titleNode = dom.byId('scoreChartTitle');
      if (!titleNode) {
        // insert a title <div> just before the chart
        titleNode = domConstruct.create('div', {
          id: 'scoreChartTitle',
          'class': 'scoreChartTitle'
        }, chartNode, 'before');
      }
      titleNode.textContent = text || '';
    },

    // Render (or re-render) the bar chart in the fixed #scoreChart div
    _renderChart: function(seriesData) {
      var node = dom.byId('scoreChart');
      if (!node) return;

      if (this._chart) { this._chart.destroy(); this._chart = null; }

      // Map data to Dojo series format
      var series = seriesData.map(function(d, i){
        return { x: i + 1, y: d.y, tooltip: d.tooltip };
      });

      var chart = new Chart(node);
      chart.setTheme(themeClaro);

      chart.addPlot('default', {
        type: ColumnsPlot,
        gap: 6,
        animate: false        // <- disable animated redraws
      });

      chart.addAxis('x', {
        labels: seriesData.map(function(d, i){ return { value: i+1, text: d.label }; }),
        natural: true,
        minorTicks: false,
        majorTickStep: 1
      });

      chart.addAxis('y', {
        vertical: true,
        includeZero: true,
        min: 0,
        max: 100,             // fixed 0–100 for percent scale
        majorTickStep: 20,
        fixUpper: 'minor',
        title: 'Weighted Score',
        titleOrientation: 'axis',
        titleGap: 6
      });

      chart.addSeries('Weighted Score', series, {
        stroke: null,
        outline: null,
        shadow: null,
        fill: '#4a90e2'
      });

      // Keep tooltips; they don't animate the bars
      new Tooltip(chart, 'default');

      chart.render();
      this._chart = chart;

    },

    // Run onOpen when receiving a message from OremLayerSymbology
    onReceiveData: function(name, widgetId, data, historyData) {
      if (name !== 'Housing') return;
      wLS._updateScores();
    },

    onClose: function() {
      console.log('onClose');
      if (this._chart) { this._chart.destroy(); this._chart = null; }
      if (this._legend) { this._legend.destroyRecursive(); this._legend = null; }

      wLS.publishData({ message: 'remove_location' });
    }
  });
});
