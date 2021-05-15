pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        //两代币的合约地址不能相同，即不能为相同代币
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        //排序，地址类型为uint160，可以比较大小
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        //验证两地址不为0，又因为 token0 < token1, 故 token1 != 0
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        //验证配对交易未被创建
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        //获取交易对模板合约 Uniwswap 的创建字节码 creationCode, 返回包含创建合约字节码的内存字节数组 bytes
        //creationCode 主要用来在内联汇编中自定义创建流程，尤其是使用creat2操作码
        //不能在合约本身或者继承合约中获取此属性，否则会导致循环引用
        bytes memory bytecode = type(UniswapV2Pair).creationCode; 
        //计算盐值(bytes32), 用于和创建合约的字节码、构造函数参数一同得出创建合约的地址。比使用nonce更灵活
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        //构造函数
        /*
        * creat2(v, p, n, s) 
        * v : 发送到新合约的eth数量  p : 代码的起始内存地址  n : 代码长度   s : salt
        * create new contract with men[p...p(p+n)] at adress keccak256(0xff.this.s.kecak256(men[p...p(p+n)])
        * and send v wei and return the new address, where 0xff is a 1 byte value, this is the current 
        * contract's address as a 20 byte value and s is the big-endian 256-bit value
        */

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        //调用 pair 合约的初始化方法， 传入排序后的 token 地址(create2函数创建合约时无法提供构造器参数来初始化)
        IUniswapV2Pair(pair).initialize(token0, token1);
        //双向记录同一交易对
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        //将新交易对地址传入数组以便于合约外部索引和遍历
        allPairs.push(pair);
        //触发交易对创建事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
        //设置税收地址
    function setFeeTo(address _feeTo) external {
        //要求当前方法的调用者为税务员地址
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }
        //转让税务员地址
    function setFeeToSetter(address _feeToSetter) external {
        //要求当前方法的调用者为现税务员地址
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
/* solidity0.6.2 后加盐创建合约的新方式：
        
          pragma solidity >0.6.1 <0.7.0;

          contract D {
            uint public x;
            constructor(uint a) public {
            x = a;
            }
          }

          contract C {
            function createDSalted(bytes32 salt, uint arg) public {
                /// This complicated expression just tells you how the address
                /// can be pre-computed. It is just there for illustration.
                /// You actually only need ``new D{salt: salt}(arg)``.
                address predictedAddress = address(unit160(unit(keccak256(abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    salt,
                    keccak256(abi.encodePacked(
                        type(D).creationCode,
                    arg
                    ))
                )))));

                D d = new D{salt: salt}(arg);
                require(address(d) == predictedAddress);
            }
        }
        */
