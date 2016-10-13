window.onload = function() {
  $('.accordion').accordion();

  var serviceOutagePanes = document.querySelectorAll('.service-outages-pane');
  for (var idx = 0; idx < serviceOutagePanes.length; ++idx) {
    var outerPane = serviceOutagePanes[idx];
    var service = outerPane.dataset.service;

    // Get the data
    d3.json('/outages.json?service=' + service, function(error, data) {
      if (error) throw error;

      var service = data.service;
      var pane = document.querySelector('.service-outages-pane[data-service="' + service + '"]');
      console.log(pane);

      var outages = data.outages;

      var margin = {top: 20, right: 10, bottom: 40, left: 10};
      var width = pane.offsetWidth - margin.left - margin.right;
      var height = pane.offsetHeight - margin.top - margin.bottom;

      var xScale = d3.scaleTime().range([0, width]);
      var yScale = d3.scaleLinear().range([height, 0]);

      var svg = d3.select(pane).append('svg')
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform",
              "translate(" + margin.left + "," + margin.top + ")");

      // format the data
      outages.forEach(function(d) {
        d.start_time = new Date(d.start_time * 1000);
        d.end_time = new Date(d.end_time * 1000);
      });

      twoWeeksAgo = new Date();
      twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

      // Scale the range of the data
      xScale.domain([twoWeeksAgo, new Date()]);
      yScale.domain([0, 1]);

      var rects = svg.selectAll('rect').data(outages)

      rects.enter()
        .append('rect')
        .attr('class', 'outage')
        .attr('x', function(d, i) { return xScale(d.start_time); })
        .attr('y', 0)
        .attr('width', function(d, i) { return xScale(d.end_time) - xScale(d.start_time); })
        .attr('height', function(d, i) { return yScale(0); });

      // Add the X Axis
      svg.append('g')
        .attr('transform', 'translate(0,' + height + ')')
        .call(d3.axisBottom(xScale).ticks(4));

      // Add the Y Axis
      svg.append('g')
        .call(d3.axisLeft(yScale).ticks(0));
    });
  }


  var serviceRequestPanes = document.querySelectorAll('.service-requests-pane');
  for (var idx = 0; idx < serviceRequestPanes.length; ++idx) {
    var outerPane = serviceRequestPanes[idx];
    var service = outerPane.dataset.service;

    // Get the data
    d3.json('/requests.json?service=' + service, function(error, data) {
      if (error) throw error;

      var service = data.service;
      var pane = document.querySelector('.service-requests-pane[data-service="' + service + '"]');

      var successes = data.successes;
      var errors = data.errors;

      var margin = {top: 20, right: 10, bottom: 40, left: 10};
      var width = pane.offsetWidth - margin.left - margin.right;
      var height = pane.offsetHeight - margin.top - margin.bottom;

      var xScale = d3.scaleTime().range([0, width]);
      var yScale = d3.scaleLinear().range([height, 0]);

      var svg = d3.select(pane).append('svg')
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform",
              "translate(" + margin.left + "," + margin.top + ")");

      // format the data
      errors.forEach(function(d) {
        d.time = new Date(d.time * 1000);
      });

      successes.forEach(function(d) {
        d.time = new Date(d.time * 1000);
      });

      twoWeeksAgo = new Date();
      twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

      // Scale the range of the data
      xScale.domain([twoWeeksAgo, new Date()]);
      yScale.domain([0, d3.max([errors, successes], function(d1) {
        return d3.max(d1, function(d) { return d.count; });
      })]);

      // define the line
      var valueline = d3.line()
        .x(function(d) { return xScale(d.time); })
        .y(function(d) { return yScale(d.count); });

      svg.append('path')
        .data([successes])
        .attr('class', 'line successes')
        .attr('d', valueline);

      svg.append('path')
        .data([errors])
        .attr('class', 'line errors')
        .attr('d', valueline);

      // Add the X Axis
      svg.append('g')
        .attr('transform', 'translate(0,' + height + ')')
        .call(d3.axisBottom(xScale).ticks(4));

      // Add the Y Axis
      svg.append('g')
        .call(d3.axisLeft(yScale).ticks(0));
    });
  }
};
