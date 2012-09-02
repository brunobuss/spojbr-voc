var contestname = "";

function formatTime (minutes) {

  var res = "";
  var hours = Math.floor(minutes/60);
  var mins = minutes%60;

  if(hours < 10) res += '0';
  res += hours + 'h';

  if(mins < 10) res += '0';
  res += mins + 'm';  

  return res;
};

function updateScoreboard() {

  $.getJSON(contestname + '/scoreboard', function(data){
    
    //console.log(data);

    var changed = 0;
    var pos = 0;

    for (var team in data) {

      if($("#user_" + data[team][0]).index() != pos){
        changed = 1;
        break;
      }

      pos++;
    }    

    if(changed == 0) return;

    $("#scoreboard").hide();

    for (var team in data.reverse()) {

      //console.log(data[team]);
      
      var team_tr_id = 'user_' + data[team][0];

      
      
      $("#" + team_tr_id + '> #acs').html(data[team][1]);
      $("#" + team_tr_id + '> #penalty').html(data[team][2]);

      for (var i = 3; i < data[team].length; i++) {
        var accepted_time = data[team][i][0];
        var submissions = data[team][i][1];

        var text = "";

        if(accepted_time != -1){
          text = formatTime(accepted_time) + ' (' + submissions + ')';
        }
        else {
          text = '--:-- (' + submissions + ')';
        }

        $("#" + team_tr_id + '> #prob' + (i) + ' > small').html(text);

      }

      $("#" + team_tr_id).prependTo('#scoreboard_body');

      
    }

    $("#scoreboard").fadeIn(1000);

  });

};


setInterval(updateScoreboard, 5000);

