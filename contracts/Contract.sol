// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum LoanStatus { Pending, Active, Repaid }

contract Schilled {
    // Struct to store Experience details
    struct Experience {
        uint256 id;
        address owner;
        string role;
        string company;
        string startMonth;
        string startYear;
        string endMonth;
        string endYear;
        string employmentType;
        string[] responsibilities; // Array of responsibilities
        string[] skills; // Array of skills
    }

    // Mappings to store experiences by id and experience ids
    mapping(uint256 => Experience) public experiences;
    uint256[] public experiencesIds;

    // Total number of experiences
    uint256 public totalExperieceCount = 0;

    // Private function to generate a unique id for experiences
    function generateUniqueId() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, address(this))));
    }

    // Function to add a new experience
    function addExperience(
        string memory _role,
        string memory _company,
        string memory _startMonth,
        string memory _startYear,
        string memory _endMonth,
        string memory _endYear,
        string memory _employmentType,
        string[] memory _responsibilities,
        string[] memory _skills
    ) public returns (uint256) {
        uint256 id = generateUniqueId();
    
        // Create and store the experience with added responsibilities and skills
        experiences[id] = Experience(
            id,
            msg.sender,
            _role,
            _company,
            _startMonth, 
            _startYear,
            _endMonth,
            _endYear,
            _employmentType,
            _responsibilities, // Store the responsibilities
            _skills // Store the skills
        );

        experiencesIds.push(id);
        totalExperieceCount++;

        return id;
    }

    // Function to get all experiences
    function getExperiences() public view returns (Experience[] memory) {
        Experience[] memory allExperiences = new Experience[](totalExperieceCount);

        for (uint i = 0; i < experiencesIds.length; i++) {
            allExperiences[i] = experiences[experiencesIds[i]];
        }

        return allExperiences;
    }

    // Function to get all experiences of a specific user
    function getUserExperience(address _owner) public view returns (Experience[] memory) {
        uint userExperienceCount = 0;
        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].owner == _owner) {
                userExperienceCount++;
            }
        }

        Experience[] memory userExperiences = new Experience[](userExperienceCount);
        uint index = 0;

        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].owner == _owner) {
                userExperiences[index] = experiences[experiencesIds[i]];
                index++;
            }
        }

        return userExperiences;
    }
}