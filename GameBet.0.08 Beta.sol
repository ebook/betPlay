// 胜，负，平 竞猜游戏。
// https://gitter.im/BetPlay/Lobby
// Address 0xd45456ce0a003a1387e60cbf5cf4c6a1b0387f87
pragma solidity ^0.4.24;
import './SafeMath.sol';
contract GameBet{
	using SafeMath for uint256;
	event gameCreated(bytes32 indexed game_id,address indexed creator, string home, string away, uint16 indexed category, uint64 locktime);
	event betting(bytes32 indexed game_id, address bidder, uint amount, Results results);
	event tipSettlement(address beneficiary,uint amount);
	event gameVerified(bytes32 indexed game_id);
	event withdrawal(address indexed user, uint amount, uint timestamp);
	enum Status { Pending, Open, Locked, Cancel, Verified, Over }
	enum Results {Home, Away, Draw}

	struct Bet{
		address bettor;
		Results	betting;
		uint256 amount;
	}
	struct Game{
		address owner;
		string	title;
		string	home;
		string	away;
		string	hImg;
		string	aImg;
		uint16	category;
		uint64	locktime;
		Status	status;
		Results	results;
	} 
	address Referee=0x0E807c3Aa2D37B8fF01d6A4d1A593F0E720F4D0c;
	address Owner  =0x4260c2eF8652B8DB942F71C70AE2C1c1a005d061;
	mapping(bytes32 => address[]) public mBettors;		// game id mapping to Bettors list. For record the withdrawals state
	mapping(bytes32 => Bet[]) public mBets;	  				// game id mapping to Bet bid list.
	mapping(bytes32 => Game) public mGame;    				// game id mapping.
	mapping(bytes32 => uint) public mBetCount;				// Game id mapping to it's bet count.
	bytes32[] public gameId;
	uint public gamesCount=0;

	function CreateBet(string _title,string	_home,string	_hImg,string	_away,string	_aImg,uint16	_category,uint64 _locktime) 
		public returns (bool){
		//require(!(msg.value == 0.60 ether),"Lack of balance! need 0.60 ETH.");
		bytes32 id=keccak256(abi.encodePacked(_home,_away,_title));
		require(!(mGame[id].locktime == _locktime),"Bet already exist.");
		mGame[id]=(Game({
			owner: msg.sender,
			title:_title,
			home:_home,
			hImg:_hImg,
			away:_away,
			aImg:_aImg,
			category:_category,
			locktime:_locktime,
			status:Status.Pending,
			results:Results.Draw
		}));
		gameId.push(id);
		gamesCount++;
		emit gameCreated(id,msg.sender,_home, _away, _category, _locktime);
		return true;
	}
	
	function Betting(bytes32 _game_id,Results _betting) public payable returns (bool) { 
		require((mGame[_game_id].status==Status.Open),"The game bet is not valuable!");
		require(!(msg.sender == Referee),"Administror can not betting!");
		mBets[_game_id].push(Bet({bettor: msg.sender, betting: _betting, amount: msg.value}));
		mBettors[_game_id].push(msg.sender);
		mBetCount[_game_id]++;
		emit betting(_game_id, msg.sender, msg.value, _betting);
		return true;
	}
	
	function Admin(bytes32 _game_id, Results _results,Status _status) public{
		require(msg.sender==Referee);
		mGame[_game_id].results = _results;
		mGame[_game_id].status = _status;
		if(Status.Verified == _status){
			uint256[3] memory coin = Funds(_game_id,Referee);
			uint256 gCoin = coin[2].div(100).mul(5);
			mGame[_game_id].owner.transfer(gCoin);					//Reward the Game Creator
			Owner.transfer(gCoin);													//Reward the Contract Creator
			emit tipSettlement(mGame[_game_id].owner,gCoin);
		}
		if(Status.Over == _status){
			for(uint i=0; i<mBettors[_game_id].length;i++){
				uint256[3] memory coin = Funds(_game_id ,mBettors[_game_id][i]);
				uint256 gCoin = coin[2].mul(9).div(10).mul(coin[1]).div(coin[0])+coin[1];
				mBettors[_game_id][i].transfer(gCoin);
			}									
			emit clearPool(mGame[_game_id].owner,gCoin);
		}
		emit gameVerified(_game_id);
	}
	
	// 统计指定游戏的资金池，返回数组 【1】押主场胜 【2】押平局 【3】押客场胜 【4】总资金【5】总人次
	function BetView(bytes32 _game_id) public view returns (uint256[5]){
		uint256[5] memory coin;
		for (uint i = 0; i < mBets[_game_id].length; i++) {
			if(mBets[_game_id][i].betting == Results.Home){
				coin[0] = coin[0].add(mBets[_game_id][i].amount);
			}else if(mBets[_game_id][i].betting == Results.Draw){
				coin[1] = coin[1].add(mBets[_game_id][i].amount);
			}else{
				coin[2] = coin[2].add(mBets[_game_id][i].amount);
			}
			coin[3]=coin[3].add(mBets[_game_id][i].amount);
			coin[4]+=1;
		}
		return coin;
	}
	// 统计当前用户在指定游戏中赢得的硬币数 ，返回数组 【1】所有赢家的投注 【2】我的正确投注 【3】所有的失败投注
	function Funds(bytes32 _game_id,address sender) public view returns(uint256[3]){
		uint256[3] memory coin;
    for (uint i = 0; i < mBets[_game_id].length; i++) {
			if(mBets[_game_id][i].betting == mGame[_game_id].results){
				coin[0] = coin[0].add(mBets[_game_id][i].amount);
				if(mBets[_game_id][i].bettor == sender){
					coin[1] = coin[1].add(mBets[_game_id][i].amount);
				}
			}else{
				coin[2] = coin[2].add(mBets[_game_id][i].amount);
			}
		}
		return coin;
	}
	
	function Bettors(bytes32 _game_id) private returns(bool){
		bool rtn = false;
		for(uint i=0; i<mBettors[_game_id].length;i++){
			if(mBettors[_game_id][i]== msg.sender){
				delete mBettors[_game_id][i];
				rtn= true;
			}
		}
		return rtn;
	}
	
	function Withdraw(bytes32 _game_id) public {
		require(mGame[_game_id].status == Status.Verified,"Game result not verified!");
		require(Bettors(_game_id),"Already liquidated!");
		uint256[3] memory coin = Funds(_game_id ,msg.sender);
		//gCoin= lCoin*(wCoin*0.9/sCoin)+wCoin;
		uint256 gCoin = coin[2].mul(9).div(10).mul(coin[1]).div(coin[0])+coin[1];
		msg.sender.transfer(gCoin);
		emit withdrawal(msg.sender, gCoin, now);
	}
}