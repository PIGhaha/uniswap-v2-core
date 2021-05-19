//交易对(pair)合约的父合约，实现了ERC20代币功能并增加了对线下签名消息进行授权的支持。
pragma solidity =0.5.16;

//合约实现的接口代表了它的基本功能
import './interfaces/IUniswapV2ERC20.sol';
//防溢出数学工具库
import './libraries/SafeMath.sol';

//定义了该合约必须实现导入的 IUniswapV2ERC20 接口，该接口是由标准ERC20接口加上自定义的线下签名消息支持接口
//组成。所以UniswapV2ERC20 也是一个ERC20代币合约
contract UniswapV2ERC20 is IUniswapV2ERC20 {
    //using A for *; 的效果是，库 A 中的函数被附加在任意的类型上。
    //using A for B;通过引入一个模块，不需要再添加代码就可以使用包括库函数在内的数据类型。
    //在这两种情况下，所有函数都会被附加一个参数，即使它们的第一个参数类型与对象的类型不匹配。函数调用和
    //重载解析时才会做类型检查
    using SafeMath for uint;
    
    //定义三个对外状态变量(代币元数据):名称、符号和精度(小数点位数)
    //所有代币的合约代码都是相同的，唯一区别是合约地址
    string public constant name = 'Uniswap V2';
    string public constant symbol = 'UNI-V2';
    uint8 public constant decimals = 18;
    //记录代币发行总量
    //pubilc 利用编译器的自动构造同名函数功能实现相应接口
    uint  public totalSupply;
    //记录每个地址的代币余额
    mapping(address => uint) public balanceOf;
    //记录每个地址的授权分布，用于非直接转移代币(例如第三方合约来转移)
    mapping(address => mapping(address => uint)) public allowance;

    //用于在不同Dapp之间区分相同结构和内容的签名消息，该值也有助于用户辨识那些为信任的Dapp
    //EIP-712提案
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    //使用 permit 函数的部分定义计算哈希值， 重建消息签名时使用 
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    //记录合约每个地址使用链下签名消息交易的数量，防止重放攻击(replay attack)
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid
        }
        //domainSeparator = hashStruct(eip712Domain)结构体本身无法直接进行hash运算，
        //所以构造器中先进行了转换，hashStruct就是指将结构体转换并计算最终hash的过程。
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                //string name 可读签名域的名称(下为代币名称)  string version 当前签名域版本
                //unit256 chainId 当前链的ID，solidity不支持直接获取该值故使用内联汇编
                //bytes32 salt 用来消除歧义的 salt， 可以作为 DMAIN_SEPARATOR 的最后措施
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }
    
    //铸币函数 internal 外部无法调用
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }
    
    //销毁函数 internal
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }
    
    //授权函数 private 函数， 只能在本合约内直接调用或在子合约中可以通过一个内部或公共的函数进行间接调用
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    //转移代币函数 private 函数
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    //用户进行授权操作的外部调用接口
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    //同上， 用户转移代币操作的外部调用接口
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    
    //代币授权转移函数， external 函数， 主要由第三方合约来调用(msg.sender即第三方合约地址，也即用户授权地址)
    function transferFrom(address from, address to, uint value) external returns (bool) {
        //如果授权额度为最大值(相当于永久授权)，调用时授权余额并不减少相应的转移代币数量(减少操作步数和gas消耗)
        if (allowance[from][msg.sender] != uint(-1)) {
            //库函数.sub(value)在调用时需要经过 SafeMath 的 require 检查，如果没有授权，会导致整个交易回滚
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
    
    //使用线下签名消息进行授权操作
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
