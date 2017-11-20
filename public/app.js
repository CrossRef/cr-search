function normaliseDoi(text) {
  var doiPrefixPattern = /^doi:/;
  var dxPrefixPattern = /^dx\.doi\.org\//;
  var httpPrefixPattern = /^http:\/\/dx\.doi\.org\//;
  var trimmedText = $.trim(text);
  
  if (doiPrefixPattern.test(trimmedText)) {
    return trimmedText.slice(4);
  } else if (dxPrefixPattern.test(trimmedText)) {
    return trimmedText.slice(11);
  } else if (httpPrefixPattern.test(trimmedText)) {
    return trimmedText.slice(18);
  } else {
    return trimmedText;
  }
}
      
function isDoi(text) {
  var normalisedText = normaliseDoi(text);
  var doiPattern = /^10\.[0-9]+\/.+$/;
  return doiPattern.test(normalisedText);
}

function refreshAdvForm() {
  $('.label-add').tooltip('hide');

  var form = $('#adv-search-expander');
  form.html('');

  var fieldArea = $('#adv-search-fields');
  fieldArea.html('');

  var addMoreArea = $('<div>').addClass('add-more-area');
  var table = $('<table>').appendTo(addMoreArea);
  var requiredSetTds = {};

  $.each(form.data('form'), function(i, field) {
    if (FIELD_VALUES[field.id]) {
      var currentVal = FIELD_VALUES[field.id].val;
      var controlGroup = $('<div>').addClass('control-group').appendTo(fieldArea);
      var label = $('<label>').addClass('control-label').text(field.label).appendTo(controlGroup);
      var controls = $('<div>').addClass('controls').appendTo(controlGroup);
      var input = $('<input>');
      var help = $('<span>').addClass('help-inline');

      input.attr('type', 'text');
      input.attr('id', field.id);
      input.val(currentVal);
      input.addClass('input-xlarge');
      input.appendTo(controls);
      help.appendTo(controls);

      if (field.help) {
        help.html(field.help);
      }

      var updateValidation = function() {
        var fieldVal = $.trim(input.val());

        controlGroup.removeClass('success');
        controlGroup.removeClass('error');

        if (fieldVal.length != 0) {
          if (field.validate) {
            var validResult = field.validate(fieldVal);
            if (validResult.valid) {
              controlGroup.addClass('success');
              help.text('');
            } else {
              controlGroup.addClass('error');
              help.text(validResult.msg);
            }
          } else {
            controlGroup.addClass('success');
          }        
        }
      }

      input.data('validate', updateValidation);

      input.change(function(e) {
        FIELD_VALUES[$(this).attr('id')] = {val: $(this).val()};
        $(this).data('validate')();
        e.preventDefault();
        return false;
      });

      input.blur(function(e) {
        $(this).data('validate')();
      });

      updateValidation();
    }

    var isAdded = FIELD_VALUES[field.id];
    var addLink = $('<a>');
    var icon = $('<i>').appendTo(addLink);
    
    if (isAdded) {
      addLink.addClass('added');
      icon.addClass('icon-check');
    } else {
      icon.addClass('icon-check-empty');
    }
      
    addLink.addClass('label label-add');
    addLink.attr('href', '#');
    addLink.append(icon);
    addLink.append('&nbsp;' + field.label);
    addLink.attr('id', field.id);
      
    addLink.click(function(e) {
      if (isAdded) {
        delete FIELD_VALUES[field.id];
      } else {
        FIELD_VALUES[field.id] = {val: ''};
      }
      refreshAdvForm();
      e.preventDefault();
      return false;
    });

    addLink.hover(function(e) { $(this).attr('style', 'text-decoration: underline'); },
                  function(e) { $(this).attr('style', ''); });

    if (field.tooltip) {
      addLink.tooltip({title: field.tooltip});
    }

    var requiredSetName = field.requiredSet ? field.requiredSet : 'optional';
    var isOptionalSet = requiredSetName === 'optional';

    if (isOptionalSet) {
      addLink.addClass('optional');
    }

    if (!requiredSetTds[requiredSetName]) {
      var t = 'At least one of:';
      var td = $('<td>');
      var tr = $('<tr>');
      
      if (isOptionalSet) {
        t = 'Optional:';
      }
      
      var labelTd = $('<td>').addClass('set-label');
      labelTd.append(t);
      
      tr.append(labelTd);
      td.appendTo(tr);
      
      if (isOptionalSet) {
        tr.appendTo(table);
      } else {
        tr.prependTo(table);
      }
      
      requiredSetTds[requiredSetName] = td;
    }
    
    var requiredSetTd = requiredSetTds[requiredSetName];
    requiredSetTd.append(addLink);
  });
  
  addMoreArea.appendTo(form);
}

function makeFieldQuery() {
  var fields = $('#adv-search-expander').data('form');
  
  var url = 'https://www.crossref.org/openurl/?';
  url += 'noredirect=true&pid=kward@crossref.org&format=unixref';

  $.each(fields, function(i, field) {
    var fieldId = field.id;
    var fieldValue = FIELD_VALUES[fieldId].val;
    url += '&' + fieldId + '=' + encodeURIComponent(fieldValue);
  });
    
  return url;
}
        
$(document).ready(function() {
  var simpleSearchHandler = function(e) {
    var searchText = $('#simple-search-text').val();
    
    if (searchText.length === 0) {
      return;
    }
    
    if (isDoi(searchText)) {
      var url = 'https://doi.org/' + normaliseDoi(searchText);
      window.location.href = url;
    } else {
      var url = '/dois?q=';
      url += encodeURIComponent(searchText);
      window.location.href = url;
    }
    
    e.preventDefault();
    return false;
  }
  
  $('#simple-search-btn').click(simpleSearchHandler);
  $('#simple-search').submit(simpleSearchHandler);
  
  $('#adv-search-kind').change(function(e) {
    var selectedKind = $(this).val();
    var searchForm = $('#adv-search-expander');
    searchForm.data('form', FIELD_KIND_LOOKUP[selectedKind]);
    refreshAdvForm();
  });
  
  $(window).resize(function (e) {
    $('#bib-search-text').width($('#bib-search-well').width() - 10);
  });

  $('#bib-search-link').on('shown', function(e) {
    $('#bib-search-text').width($('#bib-search-well').width() - 10);
  });

  $('#bib-search-text').height(200);
  
  var selectedKind = $('#adv-search-kind').val();
  $('#adv-search-expander').data('form', FIELD_KIND_LOOKUP[selectedKind]);
  refreshAdvForm();
});
