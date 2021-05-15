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
        //验证两地址不为0，token0 < token1, 故 token1 != 0
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        //验证配对交易未被创建
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        //获取交易对模板合约 Uniwswap 的创建字节码 creationCode, 返回包含创建合同字节码的内存字节数组 bytes
        //creationCode 主要用来在内联汇编中自定义创建流程，尤其是使用creat2操作码
        //不能再合约本身或者继承合约中获取此属性，否则会导致循环引用
        bytes memory bytecode = type(UniswapV2Pair).creationCode; 
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
