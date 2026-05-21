const WCV = 'https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0'
const ATO = 'https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer'

export const LAYER_DEFS = {
  w_CM: {
    url: WCV,
    query: "CenterType = 'Metropolitan Center'",
    type: 'polygon',
    color: '#a62966',
    name: 'Metropolitan Centers',
  },
  w_CU: {
    url: WCV,
    query: "CenterType = 'Urban Center'",
    type: 'polygon',
    color: '#e8572d',
    name: 'Urban Centers',
  },
  w_CC: {
    url: WCV,
    query: "CenterType = 'City Center'",
    type: 'polygon',
    color: '#f3a13e',
    name: 'City Centers',
  },
  w_CN: {
    url: WCV,
    query: "CenterType = 'Neighborhood Center'",
    type: 'polygon',
    color: '#f8dc26',
    name: 'Neighborhood Centers',
  },
  w_AA: {
    url: `${ATO}/0`,
    query: '1=1',
    type: 'polygon',
    colorExpr: ['interpolate', ['linear'], ['get', 'JOBAUTO_50'],
      0, '#feebe2', 163245, '#fbb4b9', 258193, '#f768a1', 371250, '#c51b8a', 508914, '#7a0177'],
    limit: 3600,
    name: 'Auto Access to Jobs',
  },
  w_AT: {
    url: `${ATO}/0`,
    query: '1=1',
    type: 'polygon',
    colorExpr: ['interpolate', ['linear'], ['get', 'JOBTRANSIT_50'],
      0, '#f2f0f7', 11768, '#cbc9e2', 33817, '#9e9ac8', 63893, '#756bb1', 113254, '#54278f'],
    limit: 3600,
    name: 'Transit Access to Jobs',
  },
  w_TT: {
    url: 'https://maps.rideuta.com/server/rest/services/Hosted/UTA_Stops_and_Most_Recent_Ridership/FeatureServer/0',
    query: '1=1',
    type: 'point',
    color: '#666666',
    limit: 6000,
    name: 'Transit Stops',
  },
  w_TF: {
    url: 'https://services.arcgis.com/pA2nEVnB6tquxgOW/arcgis/rest/services/Freeway_Exit_Locations/FeatureServer/0',
    query: "exitnbr IS NULL Or exitnbr IN ('002', '1', '10', '102', '104', '11', '111', '113', '114', '115', '117', '118', '12', '120', '121', '124', '125', '126', '127', '128', '129', '13', '130', '131', '132', '133', '134', '137', '14', '15', '15A', '15B', '15C', '16', '17', '18', '2', '20', '21', '22', '23', '242', '244', '248', '25', '250', '253', '257', '26', '260', '261', '263', '265', '269', '27', '271', '272', '273', '275', '276', '278', '279', '282', '284', '288', '289', '29', '291', '292', '293', '295', '297', '298', '3', '300', '301', '303', '304', '305', '305A', '305B', '305C', '305D', '306', '307', '308', '309', '310', '311', '312', '313', '314', '315', '316', '317', '319', '321', '322', '324', '325', '328', '330', '331', '332', '334', '335', '338', '339', '340', '341', '342', '343', '344', '346', '349', '351', '357', '362', '363', '365', '372', '395', '396', '397', '4', '404', '405', '5', '6', '7', '70', '8', '81', '85', '87', '9')",
    type: 'point',
    color: '#000000',
    name: 'Freeway Exits',
  },
  w_TA: {
    url: 'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Bikeways/FeatureServer/0',
    query: "(Facility1 like '%(1A)%' or Facility1 like '%(1B)%' or Facility1 like '%(2A)%' or Facility1 like '%(2B)%' or Facility1 like '%(2C)%' or Facility1 like '%Trail%') AND COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type: 'line',
    color: '#2ca25f',
    limit: 8000,
    name: 'Active Transportation',
  },
  w_AC: {
    url: 'https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Utah_Child_Care_Centers/FeatureServer/0',
    query: "COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type: 'point',
    color: '#E41A1C',
    name: 'Childcare Centers',
  },
  w_AH: {
    url: 'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/LicensedHealthCareFacilities/FeatureServer/0',
    query: "COUNTY IN ('Box Elder', 'Weber', 'Davis', 'Salt Lake', 'Utah')",
    type: 'point',
    color: '#377EB8',
    name: 'Healthcare Facilities',
  },
  w_AE: {
    urls: [
      'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_PreKto12/FeatureServer/0',
      'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_HigherEducation/FeatureServer/0',
    ],
    query: '1=1',
    type: 'point',
    color: '#4DAF4A',
    name: 'Education Institutions',
  },
  w_AG: {
    url: 'https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/UtahGroceryAndFoodStores_DAF/FeatureServer/0',
    query: 'POINT_X BETWEEN 406532.6 AND 449162.9 AND POINT_Y BETWEEN 4425359 AND 4597055',
    type: 'point',
    color: '#e7298a',
    name: 'Grocery Stores',
  },
  w_AM: {
    url: 'https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Community_Centers/FeatureServer/0',
    query: "County IN ('Box Elder', 'Weber', 'Davis', 'Salt Lake', 'Utah')",
    type: 'point',
    color: '#FF7F00',
    name: 'Community Centers',
  },
  w_AP: {
    url: 'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahParksLocal/FeatureServer/0',
    query: "COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type: 'polygon',
    color: '#A65628',
    name: 'Public Parks',
  },
}

// WFRC regional bounding box for ArcGIS REST spatial filter
export const WFRC_BBOX = '-112.5,39.8,-110.5,41.8'
